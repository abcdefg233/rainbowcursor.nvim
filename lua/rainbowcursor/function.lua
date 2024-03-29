local HCUtil=require("hcutil")
local Config=require("rainbowcursor.config")
local M={}
local H={}
local function rgb_to_colorcode(r,g,b)
 return string.format("#%02x%02x%02x",r,g,b)
end
---@class range
---@field [1] number # begin
---@field [2] number # fini
---@field [3] number # step
---@alias ranges range[]
---@param ranges ranges
---@return number[]
local function get_channel_map(ranges)
 local channel_map={}
 for _,range in ipairs(ranges) do
  local begin,fini,step=unpack(range)
  if begin==fini or step==0 then
   if begin~=channel_map[#channel_map] then
    table.insert(channel_map,begin)
   end
  else
   if begin>=fini then
    step=-step
   end
   for channel_code=begin,fini,step do
    table.insert(channel_map,channel_code)
   end
  end
 end
 return channel_map
end
---@class Color_Channel
---@field map number[]
---@field max number
---@field index number
---@field iter fun(self):number|nil
local Color_Channel={}
function Color_Channel:iter()
 self.index=self.index+1
 if self.index>self.max then
  return
 end
 return self.map[self.index]
end
---@param ranges ranges
---@return Color_Channel|number
function Color_Channel:new(ranges)
 local New=setmetatable({},{__index=self})
 New.index=ranges[1][1]+1
 New.map=get_channel_map(ranges)
 New.max=#New.map
 if New.max==1 then
  return New.map[1]
 end
 return New
end
---@class Color_Object
---@field iter fun(self):fun():number[]|nil
---@field static_channels number[] # code of channels.
---@field dynamic_channels Color_Channel[]
local Color_Object={}
function Color_Object:iter()
 return function()
  for index,channel in pairs(self.dynamic_channels) do
   local code=channel:iter()
   if code==nil then return end
   self.static_channels[index]=code
  end
  return self.static_channels
 end
end
---@param ranges ranges
---@return Color_Object
function Color_Object:new(ranges)
 local New=setmetatable({},{__index=self})
 New.static_channels={}
 New.dynamic_channels={}
 for index,range in ipairs(ranges) do
  local Channel=Color_Channel:new(range)
  if type(Channel)=="number" then
   New.static_channels[index]=Channel
  else
   New.dynamic_channels[index]=Channel
  end
 end
 return New
end
---@class Color_Table
---@field tab table[]
---@field index integer
---@field fini integer
local Color_Table={}
function Color_Table:iter(step)
 local code=self.tab[math.floor(self.index+1)]
 self.index=(self.index+step)%self.fini
 return code
end
function Color_Table:new()
 local New=setmetatable({},{__index=self})
 local color_object=Color_Object:new(Config.options.rainbowcursor.channels)
 New.tab={}
 for channel_values in color_object:iter() do
  local r,g,b=H.format(unpack(channel_values))
  local color_code=rgb_to_colorcode(r,g,b)
  table.insert(New.tab,{bg=color_code})
 end
 New.fini=#New.tab
 New.index=1
 return New
end
---@param interval number
local function create_color_iter(color_table,interval)
 local hlgroup=Config.options.rainbowcursor.hlgroup
 local step=color_table.fini/interval
 return function()
  vim.api.nvim_set_hl(0,hlgroup,color_table:iter(step))
 end
end
local function set_cursor_hlgroup(hlgroup)
 local guicursor={}
 for item in string.gmatch(vim.o.guicursor,"[^,]+") do
  item=string.match(item,"^.+:[^-]+")
  if hlgroup then
   item=item.."-"..hlgroup
  end
  table.insert(guicursor,item)
 end
 vim.opt.guicursor=guicursor
end
---@param target boolean
local update_cursor_hlgroup=vim.schedule_wrap(function(target)
 if target~=H.hlgroup_on then
  if target==true then
   set_cursor_hlgroup(Config.options.rainbowcursor.hlgroup)
   H.hlgroup_on=true
  elseif not (H.Timer.main:is_active() and H.Autocmd.main.active) then
   set_cursor_hlgroup(false)
   H.hlgroup_on=false
  end
 end
end)
local Actions={}
M.Actions=Actions
Actions.Timer={
 Start=function()
  if H.Timer.main:is_active()==false then
   H.Timer.main:start(0,H.Timer.interval,H.Timer.color_iter)
   update_cursor_hlgroup(true)
  end
 end,
 Stop=function()
  if H.Timer.main:is_active()==true then
   H.Timer.main:stop()
   update_cursor_hlgroup(false)
  end
 end,
 Toggle=function()
  if H.Timer.main:is_active()==true then
   H.Timer.main:stop()
   update_cursor_hlgroup(false)
  else
   H.Timer.main:start(0,H.Timer.interval,H.Timer.color_iter)
   update_cursor_hlgroup(true)
  end
 end,
}
Actions.Autocmd={
 Start=function()
  if H.Autocmd.main.active==false then
   H.Autocmd.main:start()
   update_cursor_hlgroup(true)
  end
 end,
 Stop=function()
  if H.Autocmd.main.active==true then
   H.Autocmd.main:delete()
   update_cursor_hlgroup(false)
  end
 end,
 Toggle=function()
  if H.Autocmd.main.active==true then
   H.Autocmd.main:delete()
   update_cursor_hlgroup(false)
  else
   H.Autocmd.main:start()
   update_cursor_hlgroup(true)
  end
 end,
}
Actions.RainbowCursor={
 Timer=Actions.Timer,
 Autocmd=Actions.Autocmd,
 Start=function()
  Actions.Autocmd.Start()
  Actions.Timer.Start()
 end,
 Stop=function()
  Actions.Autocmd.Stop()
  Actions.Timer.Stop()
 end,
 Toggle=function()
  Actions.Autocmd.Toggle()
  Actions.Timer.Toggle()
 end,
}
function M.RainbowCursor(...)
 local args={...}
 local action=Actions.RainbowCursor
 for i=1,#args do
  action=action[args[i]]
  if action==nil then return end
  if type(action)=="function" then
   action()
   return
  end
 end
end
local function satus_setup()
 H.hlgroup_on=false
end
local function timer_setup()
 H.Timer           ={}
 H.Timer.main      =vim.loop.new_timer()
 H.Timer.interval  =Config.options.rainbowcursor.timer.interval
 local color_iter  =create_color_iter(H.color_table,Config.options.rainbowcursor.timer.loopover)
 ---@type function
 H.Timer.color_iter=vim.schedule_wrap(color_iter)
end
local function autocmd_setup()
 H.Autocmd           ={}
 local color_iter    =create_color_iter(H.color_table,Config.options.rainbowcursor.autocmd.loopover)
 ---@type function
 H.Autocmd.color_iter=vim.schedule_wrap(color_iter)
 H.Autocmd.main      =HCUtil.Autocmd:create(Config.options.rainbowcursor.autocmd.group,{
  {Config.options.rainbowcursor.autocmd.event,{callback=H.Autocmd.color_iter}},
 })
end
local function format_setup()
 local default_formats=require("rainbowcursor.format")
 local default_format=default_formats[Config.options.rainbowcursor.channels.format]
 if default_formats[Config.options.rainbowcursor.channels.format] then
  H.format=default_format
 elseif type(Config.options.rainbowcursor.channels.format)=="function" then
  H.format=Config.options.rainbowcursor.channels.format
 end
end
function M.setup()
 H={}
 format_setup()
 satus_setup()
 H.color_table=Color_Table:new()
 timer_setup()
 autocmd_setup()
 M.TimerColorIter  =H.Timer.color_iter
 M.AutocmdColorIter=H.Autocmd.color_iter
end
return M
