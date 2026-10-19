// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's word when a Claude Code session waits on the person.
struct ClaudeAttentionStrings {
    let alert: String
    let alertHint: String
    let needsYou: (String) -> String
    let permission: String
    let question: String
    let waiting: String

    func reason(_ reason: ClaudeWaitingSession.Reason) -> String {
        switch reason {
        case .permission: return permission
        case .input: return question
        case .dialog, .other: return waiting
        }
    }
}

/// Murmur's dictation, shown in the island in place of its own overlay.
struct DictationStrings {
    let title: String
    let hint: String
    let listening: String
    let locked: String
    let command: String
    let transcribing: String
    let typed: String
}

extension FeatureStrings {
    static func claudeAttention(_ language: AppLanguage) -> ClaudeAttentionStrings {
        switch language {
        case .enUS: return ClaudeAttentionStrings(
            alert: "When Claude needs you",
            alertHint: "Shows in the island when a Claude Code session stops for a permission prompt or a question. Click it to go to that session’s terminal tab.",
            needsYou: { "\($0) needs you" }, permission: "Permission", question: "Question", waiting: "Waiting")
        case .ptBR: return ClaudeAttentionStrings(
            alert: "Quando o Claude precisar de você",
            alertHint: "Aparece na ilha quando uma sessão do Claude Code para em um pedido de permissão ou em uma pergunta. Clique para ir à aba do terminal dessa sessão.",
            needsYou: { "\($0) precisa de você" }, permission: "Permissão", question: "Pergunta", waiting: "Aguardando")
        case .tr: return ClaudeAttentionStrings(
            alert: "Claude sizi beklediğinde",
            alertHint: "Bir Claude Code oturumu izin istemi veya soru için durduğunda adada görünür. O oturumun terminal sekmesine gitmek için tıklayın.",
            needsYou: { "\($0) sizi bekliyor" }, permission: "İzin", question: "Soru", waiting: "Bekliyor")
        case .ru: return ClaudeAttentionStrings(
            alert: "Когда Claude ждёт вас",
            alertHint: "Появляется на острове, когда сеанс Claude Code останавливается на запросе разрешения или вопросе. Нажмите, чтобы перейти к вкладке терминала этого сеанса.",
            needsYou: { "\($0) ждёт вас" }, permission: "Разрешение", question: "Вопрос", waiting: "Ожидание")
        case .es: return ClaudeAttentionStrings(
            alert: "Cuando Claude te necesite",
            alertHint: "Aparece en la isla cuando una sesión de Claude Code se detiene en una solicitud de permiso o una pregunta. Haz clic para ir a la pestaña del terminal de esa sesión.",
            needsYou: { "\($0) te necesita" }, permission: "Permiso", question: "Pregunta", waiting: "En espera")
        case .sk: return ClaudeAttentionStrings(
            alert: "Keď vás Claude potrebuje",
            alertHint: "Zobrazí sa na ostrove, keď sa relácia Claude Code zastaví pri žiadosti o povolenie alebo otázke. Kliknutím prejdete na kartu terminálu tejto relácie.",
            needsYou: { "\($0) vás potrebuje" }, permission: "Povolenie", question: "Otázka", waiting: "Čaká")
        case .de: return ClaudeAttentionStrings(
            alert: "Wenn Claude dich braucht",
            alertHint: "Erscheint auf der Insel, wenn eine Claude-Code-Sitzung bei einer Berechtigungsanfrage oder einer Frage anhält. Klicke darauf, um zum Terminal-Tab dieser Sitzung zu wechseln.",
            needsYou: { "\($0) braucht dich" }, permission: "Berechtigung", question: "Frage", waiting: "Wartet")
        case .fr: return ClaudeAttentionStrings(
            alert: "Quand Claude a besoin de vous",
            alertHint: "S’affiche sur l’île quand une session Claude Code s’arrête sur une demande d’autorisation ou une question. Cliquez pour aller à l’onglet du terminal de cette session.",
            needsYou: { "\($0) a besoin de vous" }, permission: "Autorisation", question: "Question", waiting: "En attente")
        case .it: return ClaudeAttentionStrings(
            alert: "Quando Claude ha bisogno di te",
            alertHint: "Appare sull’isola quando una sessione di Claude Code si ferma su una richiesta di autorizzazione o una domanda. Fai clic per andare alla scheda del terminale di quella sessione.",
            needsYou: { "\($0) ha bisogno di te" }, permission: "Autorizzazione", question: "Domanda", waiting: "In attesa")
        case .ja: return ClaudeAttentionStrings(
            alert: "Claude が応答を待っているとき",
            alertHint: "Claude Code のセッションが許可の確認や質問で止まると、アイランドに表示されます。クリックするとそのセッションのターミナルタブに移動します。",
            needsYou: { "\($0) が待っています" }, permission: "許可", question: "質問", waiting: "待機中")
        case .ko: return ClaudeAttentionStrings(
            alert: "Claude가 응답을 기다릴 때",
            alertHint: "Claude Code 세션이 권한 요청이나 질문에서 멈추면 아일랜드에 표시됩니다. 클릭하면 해당 세션의 터미널 탭으로 이동합니다.",
            needsYou: { "\($0) 응답 대기 중" }, permission: "권한", question: "질문", waiting: "대기 중")
        case .uk: return ClaudeAttentionStrings(
            alert: "Коли Claude чекає на вас",
            alertHint: "З’являється на острові, коли сеанс Claude Code зупиняється на запиті дозволу або питанні. Натисніть, щоб перейти до вкладки термінала цього сеансу.",
            needsYou: { "\($0) чекає на вас" }, permission: "Дозвіл", question: "Питання", waiting: "Очікування")
        case .zhHans: return ClaudeAttentionStrings(
            alert: "Claude 需要你时",
            alertHint: "当 Claude Code 会话因权限请求或提问而暂停时，会在灵动岛中显示。点按即可前往该会话的终端标签页。",
            needsYou: { "\($0) 需要你" }, permission: "权限", question: "问题", waiting: "等待中")
        case .zhTW: return ClaudeAttentionStrings(
            alert: "Claude 需要你時",
            alertHint: "當 Claude Code 工作階段因權限請求或提問而暫停時，會在動態島中顯示。按一下即可前往該工作階段的終端機標籤頁。",
            needsYou: { "\($0) 需要你" }, permission: "權限", question: "問題", waiting: "等待中")
        case .zhHK: return ClaudeAttentionStrings(
            alert: "Claude 需要你時",
            alertHint: "當 Claude Code 工作階段因權限請求或提問而暫停時，會在動態島中顯示。按一下即可前往該工作階段的終端機分頁。",
            needsYou: { "\($0) 需要你" }, permission: "權限", question: "問題", waiting: "等待中")
        }
    }

    static func dictation(_ language: AppLanguage) -> DictationStrings {
        switch language {
        case .enUS: return DictationStrings(
            title: "Murmur dictation",
            hint: "While Murmur is running, its recording shows in the island instead of its own overlay.",
            listening: "Listening", locked: "Locked", command: "Command", transcribing: "Transcribing", typed: "Typed")
        case .ptBR: return DictationStrings(
            title: "Ditado do Murmur",
            hint: "Enquanto o Murmur estiver aberto, a gravação aparece na ilha em vez da sobreposição dele.",
            listening: "Ouvindo", locked: "Travado", command: "Comando", transcribing: "Transcrevendo", typed: "Digitado")
        case .tr: return DictationStrings(
            title: "Murmur dikte",
            hint: "Murmur çalışırken kaydı kendi katmanı yerine adada görünür.",
            listening: "Dinliyor", locked: "Kilitli", command: "Komut", transcribing: "Yazıya dökülüyor", typed: "Yazıldı")
        case .ru: return DictationStrings(
            title: "Диктовка Murmur",
            hint: "Пока Murmur запущен, запись отображается на острове вместо его собственного окна.",
            listening: "Слушаю", locked: "Закреплено", command: "Команда", transcribing: "Распознавание", typed: "Введено")
        case .es: return DictationStrings(
            title: "Dictado de Murmur",
            hint: "Mientras Murmur está abierto, su grabación aparece en la isla en lugar de su propia superposición.",
            listening: "Escuchando", locked: "Bloqueado", command: "Comando", transcribing: "Transcribiendo", typed: "Escrito")
        case .sk: return DictationStrings(
            title: "Diktovanie Murmur",
            hint: "Kým je Murmur spustený, jeho nahrávanie sa zobrazuje na ostrove namiesto jeho vlastného prekrytia.",
            listening: "Počúva", locked: "Uzamknuté", command: "Príkaz", transcribing: "Prepisuje sa", typed: "Napísané")
        case .de: return DictationStrings(
            title: "Murmur-Diktat",
            hint: "Solange Murmur läuft, erscheint die Aufnahme auf der Insel statt in Murmurs eigener Einblendung.",
            listening: "Hört zu", locked: "Fixiert", command: "Befehl", transcribing: "Wird transkribiert", typed: "Eingegeben")
        case .fr: return DictationStrings(
            title: "Dictée Murmur",
            hint: "Tant que Murmur est ouvert, son enregistrement s’affiche sur l’île au lieu de sa propre fenêtre.",
            listening: "Écoute", locked: "Verrouillé", command: "Commande", transcribing: "Transcription", typed: "Saisi")
        case .it: return DictationStrings(
            title: "Dettatura Murmur",
            hint: "Mentre Murmur è aperto, la registrazione appare sull’isola invece che nel suo riquadro.",
            listening: "In ascolto", locked: "Bloccato", command: "Comando", transcribing: "Trascrizione", typed: "Inserito")
        case .ja: return DictationStrings(
            title: "Murmur の音声入力",
            hint: "Murmur の実行中は、録音状況が Murmur 自身のオーバーレイではなくアイランドに表示されます。",
            listening: "聞き取り中", locked: "ロック中", command: "コマンド", transcribing: "文字起こし中", typed: "入力済み")
        case .ko: return DictationStrings(
            title: "Murmur 받아쓰기",
            hint: "Murmur가 실행 중이면 녹음 상태가 Murmur 자체 오버레이 대신 아일랜드에 표시됩니다.",
            listening: "듣는 중", locked: "고정됨", command: "명령", transcribing: "변환 중", typed: "입력됨")
        case .uk: return DictationStrings(
            title: "Диктування Murmur",
            hint: "Поки Murmur запущено, запис показується на острові замість його власного вікна.",
            listening: "Слухаю", locked: "Закріплено", command: "Команда", transcribing: "Розпізнавання", typed: "Введено")
        case .zhHans: return DictationStrings(
            title: "Murmur 听写",
            hint: "Murmur 运行时，录音状态会显示在灵动岛中，而不是它自己的浮层。",
            listening: "正在聆听", locked: "已锁定", command: "命令", transcribing: "正在转写", typed: "已输入")
        case .zhTW: return DictationStrings(
            title: "Murmur 聽寫",
            hint: "Murmur 執行時，錄音狀態會顯示在動態島中，而不是它自己的浮層。",
            listening: "正在聆聽", locked: "已鎖定", command: "指令", transcribing: "正在轉寫", typed: "已輸入")
        case .zhHK: return DictationStrings(
            title: "Murmur 聽寫",
            hint: "Murmur 執行時，錄音狀態會顯示在動態島中，而不是它自己的浮層。",
            listening: "正在聆聽", locked: "已鎖定", command: "指令", transcribing: "正在轉寫", typed: "已輸入")
        }
    }
}
