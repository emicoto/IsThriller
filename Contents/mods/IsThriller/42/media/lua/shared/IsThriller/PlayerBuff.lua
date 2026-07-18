-- 占位骨架
-- Claude Note: myBgm模式的玩家buff(恐慌清除/兴奋加速)待实装, 草稿见 ClaudeCode/IsThriller_ExcitedBuff, 方案见规划报告
-- 也包括myBgm模式的关键进程管理
local PlayerBuff = {}

---@param st table IsThriller main object
---@param player IsoPlayer
function PlayerBuff.handle(st, player)
    -- TODO: myBgm buff handle
end


function PlayerBuff.doStart(st, player)
    st.state = "playing"
    st.music.start(player)

    -- TODO: get buff
end

function PlayerBuff.doEnd(st, player)
    -- remove buff
end

return PlayerBuff
