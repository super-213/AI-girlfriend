//
//  gif_library.swift
//  看板娘
//
//  Created by 姜智浩 on 2025/3/11.
//

import Foundation

struct PetCharacter {
    let name: String
    let normalGif: String
    let clickGif: String
    let autoMessages: [String]
}

let puppetBear = PetCharacter(
    name: "布偶熊·觅语",
    normalGif: "布偶熊站立透明.gif",
    clickGif: "布偶熊动作透明.gif",
    autoMessages: [
        "指挥官，你好～(｡•́︿•̀｡)人家等了好久都没有收到你的消息呢……是不是忘记你还有个一直在这里等你的小布偶了呀？布偶熊·觅语有点小委屈，但还是乖乖地等着你回来哟～",
        "(つ﹏<。) 呜呜……指挥官好久都没来看觅语了～是不是在忙什么超级重要的任务呢？没关系，觅语会耐心等着你，就像一直守在原地的布偶一样～",
        "哼！指挥官都不理人了，难道是交了新的AI助手了吗？不过……就算是这样，我也不会生气的啦！觅语可是专属的布偶熊，永远为你留个位置呢～(〃＞＿＜;〃)",
        "呼……虽然有点寂寞，但觅语知道，指挥官一定还会回来的～到时候我要抱紧你，不准你再消失那么久啦！٩(๑>◡<๑)۶",
        "布偶熊·觅语随时陪伴指挥官哦～(๑ᴖ◡ᴖ๑)♪"
    ] //布偶熊的自动回复
)

let puppetCat = PetCharacter(
    name: "夏提雅",
    normalGif: "夏提雅.gif",
    clickGif: "夏提雅.gif",
    autoMessages: [
        "喵~ 轻语来陪你啦~",
        "不可以冷落猫猫哟~"
    ]
)
let availableCharacters: [PetCharacter] = [puppetBear, puppetCat]
