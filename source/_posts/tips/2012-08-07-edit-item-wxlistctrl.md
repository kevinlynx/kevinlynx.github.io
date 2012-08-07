---
layout: post
title: "让wxListCtrl支持子item编辑"
date: 2012-08-07 13:48
comments: true
categories: [tips, lua]
tags: [tips, lua, wxLua]
---

我使用的wxLua版本信息为`wxLua 2.8.7.0 built with wxWidgets 2.8.8`，也就是LuaForWindows_v5.1.4-40.exe这个安装包里自带的wxLua。我不知道其他wxWidgets版本里wxListCtrl怎样，但我使用的版本里wxListCtrl是不支持编辑里面的子item的。在我使用的report模式下，子item也就是特定某一行一列的item。

google了一下，发现悲剧地需要自己实现，主要就是自己显示一个wxTextCtrl：
<!-- more -->
{% highlight lua %}
--
-- file: wxListCtrlTextEdit.lua
-- author: Kevin Lynx
-- date: 08.06.2012
--
local EditList = {}

-- get the column by an abs point
function EditList:getColumn(x)
    local cols = self.listctrl:GetColumnCount()
    local cx = 0
    for i = 0, cols - 1 do
        local w = self.listctrl:GetColumnWidth(i)
        if x <= cx + w then return i end
        cx = cx + w
    end
    return -1
end

-- when a mouse down, show a text edit control 
function EditList:onLeftDown(evt)
    if self.editor:IsShown() then
        self:closeEditor()
    end
    local p = evt:GetPoint()
    local row = evt:GetIndex()
    local col = self:getColumn(p.x)
    local rect = wx.wxListCtrlEx.GetSubItemRect(self.listctrl, row, col)
    rect:SetHeight(rect:GetHeight() + 5) -- adjust
    self.editor:SetSize(rect)
    self.editor:Show()
    self.editor:SetValue(wx.wxListCtrlEx.GetItemText(self.listctrl, row, col))
    self.editor:SetFocus()
    self.col = col
    self.row = row
end

function EditList:closeEditor()
    if not self.editor:IsShown() then return end
    self.editor:Hide()
    self.listctrl:SetItem(self.row, self.col, self.editor:GetValue())
end

function EditList:initialize()
    self.editor = wx.wxTextCtrl(self.listctrl, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTE_PROCESS_ENTER + wx.wxTE_RICH2)
    self.editor:Connect(wx.wxEVT_COMMAND_TEXT_ENTER, function () self:closeEditor() end)
    -- not work actually
    self.editor:Connect(wx.wxEVT_COMMAND_KILL_FOCUS, function () self:closeEditor() end)
    self.editor:Hide()
end

function wx.wxListCtrlTextEdit(listctrl)
    local o = {
        listctrl = listctrl,
        editor = nil,
    }
    local editlist = newObject(o, EditList)
    editlist:initialize()
    listctrl:Connect(wx.wxEVT_COMMAND_LIST_ITEM_RIGHT_CLICK, function (evt) editlist:onLeftDown(evt) end)
    listctrl:Connect(wx.wxEVT_COMMAND_LIST_ITEM_FOCUSED, function () editlist:closeEditor() end)
    return listctrl
end

{% endhighlight %}

其原理就是获取到当前鼠标点击所在的子item位置，然后在此位置显示一个wxEditCtrl即可。以上代码需要依赖我之前写的[Lua里实现简单的类-对象](http://codemacro.com/2012/08/02/simple-oo-in-lua/)中的代码，同时依赖以下针对wxListCtrl的扩展接口：

{% highlight lua %}
--
-- file: wxListCtrlExtend.lua
-- author: Kevin Lynx
-- date: 08.07.2012
-- brief: extend some util functions to wx.wxListCtrl
-- 
wx.wxListCtrlEx = {}

function wx.wxListCtrlEx.GetSubItemRect(listctrl, item, col)
    local rect = wx.wxRect()
    listctrl:GetItemRect(item, rect)
    local x = 0
    local w = 0
    for i = 0, col do
        w = listctrl:GetColumnWidth(i)
        x = x + w
    end
    return wx.wxRect(x - w, rect:GetY(), w, rect:GetHeight())
end

function wx.wxListCtrlEx.GetItemText(listctrl, item, col)
    local info = wx.wxListItem()
    info:SetId(item)
    info:SetColumn(col)
    info:SetMask(wx.wxLIST_MASK_TEXT)
    listctrl:GetItem(info)
    return info:GetText()
end

{% endhighlight %}

在我看到的wxWidgets官方文档里，其实wxListCtrl已经有`GetSubItemRect`接口，并且在另一些示例代码里，也看到了`GetItemText`接口，但是，我使用的版本里没有，所以只好自己写。基于以上，要使用这个可以支持编辑子item的wxListCtrl，可以：

{% highlight lua %}
list = wx.wxListCtrlTextEdit(wx.wxListCtrl(dialog, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxLC_REPORT))
{% endhighlight %}

也就是通过wx.wxListCtrlTextEdit这个函数做下处理，这个函数返回的是本身的wxListCtrl。当然更好的方式是使用继承之类的方式，开发一种新的控件，但在Lua中，针对usedata类型的扩展貌似只能这样了。

最好吐槽下，这个控件扩展其实很恶心。本来我打算当编辑控件失去焦点后就隐藏它，但是往编辑控件上注册KILL_FOCUS事件始终不起作用；我又打算弄个ESC键盘事件去手动取消，但显然wxTextCtrl是不支持键盘事件的。好吧，凑合用了。
 

