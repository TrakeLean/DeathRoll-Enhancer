"""Standalone minimap libraries and measured gold-button layout regressions."""
import unittest
import xml.etree.ElementTree as ET
from test_addon import ROOT, runtime


class MinimapAndLayoutTests(unittest.TestCase):
    def minimap_runtime(self):
        lua = runtime()
        lua.execute('''
            LibStub=nil
            securecallfunction=function(fn,...) return fn(...) end
            local create=CreateFrame
            frames={}
            CreateFrame=function(kind,name,parent,...)
                local frame=create()
                frames[#frames+1]=frame
                frame.GetParent=function() return parent end
                frame.SetPoint=function(self,...) self.point={...} end
                frame.GetVertexColor=function() return 1,1,1 end
                frame.CreateTexture=function(self) return CreateFrame('Texture',nil,self) end
                frame.CreateAnimationGroup=function(self) return CreateFrame('AnimationGroup',nil,self) end
                frame.CreateAnimation=function(self) return CreateFrame('Animation',nil,self) end
                return frame
            end
            Minimap=CreateFrame('Frame')
            Minimap:SetWidth(140);Minimap:SetHeight(140)
        ''')
        # Read the real XML load order, stopping after the minimap dependency chain.
        for element in ET.parse(ROOT / 'embeds.xml').getroot():
            path = ROOT / element.attrib['file'].replace('\\', '/')
            if path.suffix == '.xml':
                for child in ET.parse(path).getroot():
                    lua.execute((path.parent / child.attrib['file'].replace('\\', '/')).read_text())
            else:
                lua.execute(path.read_text())
            if 'LibDBIcon-1.0.lua' in str(path):
                break
        lua.execute('''
            local ace=LibStub:NewLibrary('AceAddon-3.0',1)
            ace.GetAddon=function() return DRE end
            DRE.ShowMainWindow=function() openedWindow=true end
            DRE.OpenOptions=function() openedOptions=true end
        ''')
        lua.execute((ROOT / 'Minimap.lua').read_text())
        return lua

    def test_standalone_icon_interactions_and_reenable(self):
        self.minimap_runtime().execute('''
            DRE:InitializeMinimap()
            local icons=LibStub('LibDBIcon-1.0')
            local button=assert(icons:GetMinimapButton('DeathRollEnhancer'))
            assert(button:IsShown() and button.db==DRE.db.profile.minimap)
            assert(button.dataObject==LibStub('LibDataBroker-1.1'):GetDataObjectByName('DeathRollEnhancer'))
            button.callbacks.OnClick(button,'LeftButton');assert(openedWindow)
            button.callbacks.OnClick(button,'RightButton');assert(openedOptions)
            button.callbacks.OnEnter(button)
            DRE:SlashCommand('minimap hide');assert(not button:IsShown())
            DRE:SlashCommand('minimap show');assert(button:IsShown())
            DRE:SlashCommand('minimap lock');assert(not button.callbacks.OnDragStart)
            DRE:SlashCommand('minimap unlock');assert(button.callbacks.OnDragStart)
            DRE:SetMinimapPosition(90)
            assert(DRE:GetMinimapPosition()==90 and math.abs(button.point[5]-75)<0.001)
            DRE:CleanupMinimap();assert(not button:IsShown())
            DRE:InitializeMinimap();assert(button:IsShown())
            assert(icons:GetMinimapButton('DeathRollEnhancer')==button)
        ''')

    def test_saved_hidden_locked_icon_survives_login_and_reinitialization(self):
        self.minimap_runtime().execute('''
            DRE.db.profile.minimap={hide=true,lock=true,minimapPos=180}
            DRE:InitializeMinimap()
            local button=LibStub('LibDBIcon-1.0'):GetMinimapButton('DeathRollEnhancer')
            for _,frame in ipairs(frames) do
                if frame.callbacks.OnEvent then frame.callbacks.OnEvent(frame,'PLAYER_LOGIN') end
            end
            assert(not button:IsShown() and not button.callbacks.OnDragStart)
            assert(math.abs(button.point[4]+75)<0.001)
            DRE:CleanupMinimap();DRE:InitializeMinimap()
            assert(not button:IsShown() and DRE:GetMinimapPosition()==180)
        ''')

    def test_gold_button_measures_caption_and_grows_with_row(self):
        lua = runtime()
        lua.execute('''
            DRE:ShowMainWindow()
            local create=CreateFrame
            captionWidth=100
            CreateFrame=function(...)
                local frame=create(...)
                frame.GetFontString=function()
                    local font=create()
                    font.GetStringWidth=function() return captionWidth end
                    return font
                end
                return frame
            end
            AceGUI.GetWidgetVersion=function() return 0 end
            AceGUI.GetNextWidgetNum=function() return 1 end
            AceGUI.RegisterWidgetType=function(_,_,constructor) makeButton=constructor end
            AceGUI.RegisterAsWidget=function(_,widget)
                widget.SetWidth=function(self,w) self.frame.width=w;self.frame:SetWidth(w) end
                widget.SetFullWidth=function(self,v) self.fullWidth=v end
                return widget
            end
        ''')
        lua.execute((ROOT / 'Libs/AceGUI-3.0/widgets/AceGUIWidget-Button.lua').read_text())
        lua.execute('''
            DRE.UI.autoRollButton=makeButton()
            local button=DRE.UI.autoRollButton
            button:SetText('Use My Gold')
            for _,width in ipairs({300,400,600,400,300}) do
                DRE:UpdateGameControlsLayout(width,false)
                assert(not button.fullWidth)
                assert(button.frame:GetWidth()>=captionWidth+30)
                assert(math.abs(42+DRE.UI.rollEdit:GetWidth()+button.frame:GetWidth()-(width-24))<0.001)
            end
            DRE:UpdateGameControlsLayout(600,false)
            local wide=button.frame:GetWidth()
            DRE:UpdateGameControlsLayout(400,false)
            assert(button.frame:GetWidth()<wide)
            DRE:UpdateGameControlsLayout(220,true);assert(button.fullWidth)
            captionWidth=170
            DRE:UpdateGameControlsLayout(300,false);assert(button.fullWidth)
            DRE:UpdateGameControlsLayout(400,false)
            assert(not button.fullWidth and button.frame:GetWidth()>=200)
        ''')
