"""Drive independent Forever clients through the addon message and system roll events."""
import unittest

from test_addon import runtime


def client(first, surname):
    lua = runtime("""
        GetAddOnMetadata = function(_, key) if key == 'X-DRE-DuelUI' then return '1' end end
        regionalNames = true
        local create = CreateFrame
        CreateFrame = function(...)
            local f = create(...)
            function f:SetAlpha(a) self.alpha = a end
            function f:GetAlpha() return self.alpha or 1 end
            return f
        end
        GameTooltip = {IsOwned=function() return false end}
    """)
    lua.execute("""
        units.player = {...}
        packets, scheduled, events = {}, {}, {}
        C_Timer.After = function(delay, callback)
            table.insert(scheduled, {at=clock+delay, run=callback})
        end
        function advance(seconds)
            local finish = clock + seconds
            while true do
                local index
                for i, timer in ipairs(scheduled) do
                    if timer.at <= finish and (not index or timer.at < scheduled[index].at) then index=i end
                end
                if not index then break end
                local timer = table.remove(scheduled,index)
                clock = timer.at
                timer.run()
            end
            clock = finish
        end
        function DRE:RegisterEvent(name, handler) events[name]=assert(self[handler or name]) end
        function fire(event, ...) events[event](DRE,event,...) end
        C_ChatInfo = {
            RegisterAddonMessagePrefix=function() return 0 end,
            SendAddonMessage=function(prefix,payload,channel,target)
                assert(#payload <= 255)
                table.insert(packets,{prefix,payload,channel,target})
                return 0
            end,
        }
        function form() return DRE.UI.groupWidgets end
        function choose(mode) form().mode:Fire('OnValueChanged', mode) end
        function add(name)
            form().nameInput:SetText(name)
            form().nameInput:Fire('OnEnterPressed')
        end
        function press(button)
            assert(not button.disabled)
            button.control:GetScript('OnClick')(button.control,'LeftButton')
        end
        DRE:OnEnable()
        DRE:ShowMainWindow('group')
    """, first, surname)
    return lua


class SharedTableTests(unittest.TestCase):
    def setUp(self):
        self.host = client('Mira', 'Summer')
        self.guest = client('Theo', 'Stone')
        self.h = self.host.execute
        self.g = self.guest.execute
        self.h("press(form().form.children[8]); add('Theo Stone')")
        self.g("units.target={'Mira','Summer'}; press(form().form.children[9])")

    @staticmethod
    def drain(lua):
        result = []
        for row in lua.globals().packets.values():
            result.append(tuple(row[i] for i in range(1, 5)))
        lua.execute("packets = {}")
        return result

    def relay(self):
        for src, dest, name in [(self.guest,self.host,'Theo Stone'), (self.host,self.guest,'Mira Summer')]:
            src.globals().advance(1)
            for prefix, payload, channel, target in self.drain(src):
                self.assertEqual(channel, 'WHISPER')
                self.assertEqual(target, dest.eval("DRE:GetUnitPlayerName('player')"))
                dest.globals().fire('CHAT_MSG_ADDON',prefix,payload,channel,name+'-LocalRealm')

    def test_join_during_tiebreak_hides_spectator_last_roll(self):
        self.h("""
            add('Arlo Strand'); choose('highRoller'); press(form().primary)
            for _, value in ipairs({92,92,55}) do
                local r = DRE.groupRound
                assert(DRE:HandleGroupRoll(r.players[r.turn], value, 100))
            end
        """)
        self.relay()
        self.g("""
            local r, b = DRE.groupRound, form().circle
            assert(r.seatRolls[1]==92 and r.seatRolls[2]==92 and not r.seatRolls[3])
            assert(b.seats[3].inactiveShade:IsShown() and not b.rollBadge:IsShown())
        """)
        self.h("assert(DRE:HandleGroupRoll('Mira Summer',89,100))")
        self.relay()
        self.g("assert(DRE.groupRound.turn==2 and DRE.groupRound.seatRolls[1]==89 and form().circle.seats[3].sittingOut)")
        self.h("assert(DRE:HandleGroupRoll('Theo Stone',54,100))")
        self.relay()
        self.g("assert(DRE.groupRound.points[1]==1 and not next(DRE.groupRound.seatRolls) and not form().circle.seats[3].inactiveShade:IsShown())")

    def test_host_reload_keeps_round_and_allows_next_roll(self):
        self.relay()
        self.h("choose('highRoller'); press(form().primary); fire('CHAT_MSG_SYSTEM','Mira Summer rolls 83 (1-100)')")
        self.relay()
        new_host = client('Mira','Summer')
        self.g("assert(DRE.groupRound.seatRolls[1]==83 and not DRE.groupRound.seatRolls[2])")

        # SavedVariables are serialized values. Transfer them without sharing Lua objects.
        def reload_value(value):
            if hasattr(value,'items'):
                return new_host.table_from({k: reload_value(v) for k,v in value.items()})
            return value
        data = reload_value(self.host.eval("DRE.db.char.sharedTable"))
        data['round']['seatRolls'] = None  # Exercise an older host checkpoint.
        # The guest sees another roll before the host crashes. Its revision
        # now matches the restored host but refers to a different turn.
        self.h("fire('CHAT_MSG_SYSTEM','Theo Stone rolls 90 (1-100)')")
        self.relay()
        self.g("assert(DRE.groupRound.points[2]==1 and DRE.groupRound.turn==1)")
        self.g("assert(not next(DRE.groupRound.seatRolls))")
        self.host = new_host
        self.h = new_host.execute
        self.h("DRE.db.char={sharedTable=...}; DRE:RestoreSharedTable(); advance(2)", data)
        self.guest.globals().advance(8)
        self.relay()
        self.h("assert(DRE.sharedTable.role=='host' and DRE.groupRound.highSeats[1]==1 and DRE.groupRound.turn==2)")
        self.g("assert(DRE:SharedHostOnline() and DRE.groupRound.highFace==83); press(form().primary)")
        self.g("assert(DRE.groupRound.seatRolls[1]==83)")
        self.h("fire('CHAT_MSG_SYSTEM','Theo Stone rolls 77 (1-100)')")
        self.relay()
        self.g("assert(DRE.groupRound.points[1]==1 and DRE.groupRound.turn==1 and DRE.groupRound.rollCount==2)")

    def test_legacy_guest_can_read_snapshot_without_seat_rolls(self):
        self.h("press(form().primary); fire('CHAT_MSG_SYSTEM','Mira Summer rolls 32 (1-100)')")
        self.guest.globals().advance(1)
        for prefix, payload, channel, _ in self.drain(self.guest):
            fields = payload.split(':')
            if fields[0] == 'J':
                fields[1] = fields[1].lower()
                self.g("DRE.sharedTable.ticket=...", fields[1])
                self.host.globals().fire('CHAT_MSG_ADDON', prefix, ':'.join(fields), channel, 'Theo Stone')
        self.relay()
        self.g("assert(DRE.groupRound.lastRoll==32 and not DRE.groupRound.seatRolls)")

    def test_guest_joining_at_result_keeps_prior_duel_payment_separate(self):
        self.h("press(form().primary); fire('CHAT_MSG_SYSTEM','Mira Summer rolls 1 (1-100)')")
        self.g("DRE.db.profile.pendingTradeWagers={{ownerGUID=DRE:GetTradeOwnerGUID(),playerName='Mira Summer'}}")
        self.relay()
        self.g("assert(DRE.groupRound.status=='finished' and DRE.db.profile.pendingTradeWagers[1].manualAssignmentRequired)")

    def test_roster_and_party_access_with_updates_queued(self):
        self.relay()
        self.h("units.party1={'Theo','Stone'}; DRE:GetGroupDraft().roster='Mira Summer'; DRE:RefreshGroupUI()")
        self.relay()
        self.g("assert(DRE:IsGroupGuest() and DRE.groupDraft.roster=='Mira Summer')")
        self.h("choose('teams'); units.party1=nil; advance(1)")
        outgoing = self.drain(self.host)
        self.assertTrue(any(p[1].endswith(':roster') for p in outgoing))
        self.assertFalse(any(p[1].startswith('S:') for p in outgoing))
        for prefix, payload, channel, _ in outgoing:
            self.guest.globals().fire('CHAT_MSG_ADDON',prefix,payload,channel,'Mira Summer')
        self.g("assert(not DRE.sharedTable and DRE.groupDraft.mode=='classic')")

    def test_host_edits_without_group_tab_visible(self):
        self.relay()
        self.h("DRE:ShowMainWindow('deathroll'); units.target={'Lena','Stone'}; assert(DRE:AddGroupPlayerFromUnit('target'))")
        self.relay()
        self.g("assert(DRE.groupDraft.roster:find('Lena Stone',1,true))")
        self.g("DRE:SetDefaultStartingRoll(500); assert(DRE.groupDraft.initialRoll=='100')")
        self.h("DRE:SetDefaultStartingRoll(250)")
        self.relay()
        self.g("assert(DRE.groupDraft.initialRoll=='250'); DRE:LeaveSharedTable(); assert(DRE:GetGroupDraft().initialRoll=='500')")

    def test_cross_realm_group_uses_each_clients_local_names(self):
        host, guest = client('Mira','Alpha'), client('Theo','Beta')
        for lua, realm in [(host,'Alpha'),(guest,'Beta')]:
            lua.execute("local realm=...; regionalNames=false; GetNormalizedRealmName=function() return realm end; DRE.groupDraft=nil",realm)
        host.execute("DRE:SlashCommand('group host'); add('Theo-Beta'); choose('teams')")
        guest.execute("DRE:SlashCommand('group join Mira-Alpha')")
        def forward(source,dest,sender,expected):
            source.globals().advance(1)
            for prefix,payload,channel,target in self.drain(source):
                self.assertEqual(target,expected)
                dest.globals().fire('CHAT_MSG_ADDON',prefix,payload,channel,sender)
        forward(guest,host,'Theo-Beta','Mira-Alpha')
        forward(host,guest,'Mira-Alpha','Theo-Beta')
        guest.execute("assert(DRE.groupDraft.roster=='Mira-Alpha\\nTheo' and DRE.groupDraft.teams.Theo)")
        host.execute("press(form().primary); fire('CHAT_MSG_SYSTEM','Mira rolls 50 (1-100)')")
        forward(host,guest,'Mira-Alpha','Theo-Beta')
        guest.execute("assert(DRE.groupRound.turn==2); press(form().primary); assert(#rolls==1)")

    def test_shuffle_modes_turns_result_and_leave(self):
        self.relay()
        self.g("assert(DRE:IsGroupGuest() and not form().form and form().lastRoll:GetText():find('Hosted by Mira Summer'))")
        self.h("choose('teams'); add('Arlo Strand'); local b=form().circle.seats[2].portraitButton; b:GetScript('OnClick')(b,'LeftButton')")
        self.h("local b=form().circle.seats[1].portraitButton; b:GetScript('OnClick')(b,'LeftButton'); press(form().shuffle)")
        self.relay()
        self.assertEqual(self.host.eval("DRE.groupDraft.roster"),self.guest.eval("DRE.groupDraft.roster"))
        self.g("assert(DRE.groupDraft.mode=='teams' and DRE.groupDraft.teams['Theo Stone']==1 and not DRE:ShuffleGroupOrder())")
        self.h("choose('highRoller'); local d=DRE:GetGroupDraft(); d.roster='Mira Summer\\nTheo Stone'; DRE:RefreshGroupUI(); press(form().primary)")
        self.relay()
        self.g("assert(DRE.groupRound.points[1]==0 and not form().primary and not DRE:CancelGroupRound())")
        # The guest also sees every native roll, sometimes before the host.
        for name, value in [('Mira Summer',75),('Theo Stone',75),('Mira Summer',80),('Theo Stone',20),
                            ('Mira Summer',60),('Theo Stone',10)]:
            if name == 'Theo Stone':
                self.g("press(form().primary); assert(form().primary.disabled)")
            msg = f'{name} rolls {value} (1-100)'
            before = self.guest.eval("DRE.groupRound.rollCount")
            self.guest.globals().fire('CHAT_MSG_SYSTEM',msg)
            self.assertEqual(self.guest.eval("DRE.groupRound.rollCount"),before)
            self.host.globals().fire('CHAT_MSG_SYSTEM',msg)
            self.relay()
            self.assertEqual(self.host.eval("DRE.groupRound.rollCount"),self.guest.eval("DRE.groupRound.rollCount"))
            self.assertEqual(self.host.eval("DRE.groupRound.turn"),self.guest.eval("DRE.groupRound.turn"))
            self.assertEqual(dict(self.host.eval("DRE.groupRound.seatRolls").items()),
                             dict(self.guest.eval("DRE.groupRound.seatRolls").items()))
        self.g("assert(DRE.groupRound.winner=='Mira Summer' and DRE.groupRound.points[1]==2 and #rolls==3)")
        self.g("assert(not DRE:GetHostedGroupStats() and #sent==0); press(form().secondary); assert(not DRE.sharedTable)")
        self.h("assert(DRE:GetHostedGroupStats().played==1 and #sent==0)")

    def test_late_join_reload_and_fragment_recovery(self):
        self.relay()
        self.h("""
            for i=1,38 do add('Long Surname '..string.rep('x',i)) end
            choose('twoLives'); press(form().primary)
            fire('CHAT_MSG_SYSTEM','Mira Summer rolls 1 (1-100)')
        """)
        self.host.globals().advance(7)
        self.drain(self.host)  # Lose the ordered roster and subsequent roll updates.
        self.guest.globals().advance(8)
        for prefix, payload, channel, _ in self.drain(self.guest):
            self.host.globals().fire('CHAT_MSG_ADDON',prefix,payload,channel,'Theo Stone')
        self.host.globals().advance(2)
        data = [p for p in self.drain(self.host) if p[1].startswith('S:')]
        newest = max(int(p[1].split(':')[2]) for p in data)
        newest_parts = [p for p in data if int(p[1].split(':')[2]) == newest]
        self.assertGreater(len(newest_parts), 2)
        def deliver(packet, sender='Mira Summer'):
            prefix, payload, channel, _ = packet
            self.guest.globals().fire('CHAT_MSG_ADDON',prefix,payload,channel,sender)
        for packet in reversed(newest_parts):
            deliver(packet,'Other Player')
        for packet in newest_parts[:-1]:
            deliver(packet)
        self.g("assert(not DRE.groupRound)")
        deliver(newest_parts[-1])
        self.g("assert(#DRE.groupRound.players==40 and DRE.groupRound.lives[1]==1)")
        # A fresh guest runtime keeps only character SavedVariables.
        saved_id = self.guest.eval("DRE.db.char.sharedTable.id")
        self.guest = client('Theo','Stone')
        self.g = self.guest.execute
        self.g("""DRE.db.char={sharedTable={role='guest',host='Mira Summer',id=...,updated=time()}}
            local send=C_ChatInfo.SendAddonMessage
            C_ChatInfo.SendAddonMessage=function() C_ChatInfo.SendAddonMessage=send; return 3 end
            DRE:RestoreSharedTable(); advance(2); assert(DRE:IsGroupGuest()); advance(8)""",saved_id)
        self.relay()
        self.g("assert(#DRE.groupRound.players==40 and DRE.groupRound.turn==2 and DRE.groupRound.lives[1]==1)")
        self.h("DRE:SlashCommand('group leave')")
        self.relay()
        self.g("assert(not DRE.groupRound and not DRE.sharedTable and form().form)")
