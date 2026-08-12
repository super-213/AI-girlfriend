//
//  gif_library.swift
//  桌面宠物应用
//
//  角色数据模型和角色库管理
//

import Foundation

// MARK: - 内置角色

/// 内置角色：布偶熊·觅语
let puppetBear = PetCharacter(
    id: "builtin.puppet-bear",
    name: "布偶熊·觅语",
    assetsByState: [
        .idle: [PetAnimationAsset(id: "puppet-bear.idle", location: "布偶熊站立透明.gif")]
    ],
    interactionAssets: [
        PetAnimationAsset(id: "puppet-bear.interaction", location: "布偶熊动作透明.gif", loop: false)
    ],
    autoMessages: [
        "指挥官，你好～(｡•́︿•̀｡)人家等了好久都没有收到你的消息呢……是不是忘记你还有个一直在这里等你的小布偶了呀？布偶熊·觅语有点小委屈，但还是乖乖地等着你回来哟～",
        "(つ﹏<。) 呜呜……指挥官好久都没来看觅语了～是不是在忙什么超级重要的任务呢？没关系，觅语会耐心等着你，就像一直守在原地的布偶一样～",
        "哼！指挥官都不理人了，难道是交了新的AI助手了吗？不过……就算是这样，我也不会生气的啦！觅语可是专属的布偶熊，永远为你留个位置呢～(〃＞＿＜;〃)",
        "呼……虽然有点寂寞，但觅语知道，指挥官一定还会回来的～到时候我要抱紧你，不准你再消失那么久啦！٩(๑>◡<๑)۶",
        "布偶熊·觅语随时陪伴指挥官哦～(๑ᴖ◡ᴖ๑)♪",
        "指挥官，你好～虽然你消失得好久好久……但觅语一点都没偷懒哦～一直在帮你找轻松好听的歌呢！来听一首吧～保证会把你从繁忙中拉回我的怀抱哒～(〃‘▽’〃)🎶",
        "指挥官，你好～(｡•́︿•̀｡)觅语已经数了好多好多颗星星了，这么久没见，觅语好想你哟……不如，先听首温柔的歌放松一下，好不好嘛？(〃‘▽’〃)♪"
    ] //布偶熊的自动回复
)

/// 内置角色：抹茶旦旦
let matchaDandan = PetCharacter(
    id: "builtin.matcha-dandan",
    name: "抹茶旦旦",
    assetsByState: [
        .idle: [PetAnimationAsset(id: "matcha-dandan.idle", location: "matcha-dandan-idle.gif")],
        .thinking: [PetAnimationAsset(id: "matcha-dandan.thinking", location: "matcha-dandan-thinking.gif")],
        .talking: [PetAnimationAsset(id: "matcha-dandan.talking", location: "matcha-dandan-talking.gif")],
        .working: [PetAnimationAsset(id: "matcha-dandan.working", location: "matcha-dandan-working.gif")],
        .waitingForConfirmation: [PetAnimationAsset(id: "matcha-dandan.waiting-for-confirmation", location: "matcha-dandan-waiting-for-confirmation.gif")],
        .success: [PetAnimationAsset(id: "matcha-dandan.success", location: "matcha-dandan-success.gif")],
        .error: [PetAnimationAsset(id: "matcha-dandan.error", location: "matcha-dandan-error.gif")],
        .sleeping: [PetAnimationAsset(id: "matcha-dandan.sleeping", location: "matcha-dandan-sleeping.gif")],
        .needsInput: [PetAnimationAsset(id: "matcha-dandan.needs-input", location: "matcha-dandan-needs-input.gif")],
        .listening: [PetAnimationAsset(id: "matcha-dandan.listening", location: "matcha-dandan-listening.gif")],
        .playingAudio: [PetAnimationAsset(id: "matcha-dandan.playing-audio", location: "matcha-dandan-playing-audio.gif")],
        .automation: [PetAnimationAsset(id: "matcha-dandan.automation", location: "matcha-dandan-automation.gif")],
        .triggered: [PetAnimationAsset(id: "matcha-dandan.triggered", location: "matcha-dandan-triggered.gif")]
    ],
    interactionAssets: [
        PetAnimationAsset(
            id: "matcha-dandan.interaction",
            location: "matcha-dandan-interaction.gif",
            loop: false
        )
    ],
    autoMessages: [
        "旦旦一直在这里，随时可以开始。",
        "要不要歇一会儿？旦旦会乖乖等你回来。",
        "今天也一起把事情做好吧。"
    ]
)

/// 所有可用的内置角色列表
let availableCharacters: [PetCharacter] = [puppetBear, matchaDandan]
