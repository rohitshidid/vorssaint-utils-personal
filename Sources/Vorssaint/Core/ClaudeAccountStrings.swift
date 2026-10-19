// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Claude accounts the AI page gives limits cards of their own. Words
/// both agents share, as the buttons and the account name, come from
/// `CodexAccountStrings`.
struct ClaudeAccountStrings {
    let title: String
    let explanation: String
    let fallback: String
    let chooseFolder: String
    let invalidFolder: String
    let signIn: String
    let update: String
    let missing: String
}

extension FeatureStrings {
    static func claudeAccounts(_ language: AppLanguage) -> ClaudeAccountStrings {
        switch language {
        case .enUS: return ClaudeAccountStrings(
            title: "Claude accounts",
            explanation: "Each CLAUDE_CONFIG_DIR folder you add gets its own limits card. While the AI Agents page is open, Claude Code checks each one about every five minutes with that folder’s own sign-in. No prompt is sent. Sessions running in Terminal under any ~/.claude-<name> folder show as working, labeled with their account.",
            fallback: "With no accounts added, Claude limits come from Claude Code’s usual folder and the Claude app.",
            chooseFolder: "Choose a Claude Code folder",
            invalidFolder: "Choose a CLAUDE_CONFIG_DIR folder, such as ~/.claude-work, with .claude.json, settings.json or projects in it. The folder must be yours and not writable by others, and .claude.json must not be a link.",
            signIn: "Run /login in Claude Code with this folder.",
            update: "Update Claude Code to check limits.",
            missing: "Install Claude Code to check limits.")
        case .ptBR: return ClaudeAccountStrings(
            title: "Contas do Claude",
            explanation: "Cada pasta CLAUDE_CONFIG_DIR adicionada ganha o próprio cartão de limites. Enquanto a página Agentes de IA está aberta, o Claude Code verifica cada uma aproximadamente a cada cinco minutos, com o login dessa pasta. Nenhum prompt é enviado. Sessões em execução no Terminal em qualquer pasta ~/.claude-<nome> aparecem como ativas, com o nome da conta.",
            fallback: "Sem contas adicionadas, os limites do Claude vêm da pasta habitual do Claude Code e do app Claude.",
            chooseFolder: "Escolha uma pasta do Claude Code",
            invalidFolder: "Escolha uma pasta CLAUDE_CONFIG_DIR, como ~/.claude-work, com .claude.json, settings.json ou projects. A pasta deve ser sua, sem permissão de escrita para outros, e o .claude.json não pode ser um link.",
            signIn: "Execute /login no Claude Code com esta pasta.",
            update: "Atualize o Claude Code para verificar os limites.",
            missing: "Instale o Claude Code para verificar os limites.")
        case .tr: return ClaudeAccountStrings(
            title: "Claude hesapları",
            explanation: "Eklediğiniz her CLAUDE_CONFIG_DIR klasörünün kendi sınır kartı olur. YZ Ajanları sayfası açıkken Claude Code her birini o klasörün kendi oturumuyla yaklaşık beş dakikada bir denetler. İstem gönderilmez. Herhangi bir ~/.claude-<ad> klasörüyle Terminal’de çalışan oturumlar, hesap adıyla birlikte çalışıyor olarak görünür.",
            fallback: "Hesap eklenmediğinde Claude sınırları Claude Code’un olağan klasöründen ve Claude uygulamasından gelir.",
            chooseFolder: "Bir Claude Code klasörü seçin",
            invalidFolder: "İçinde .claude.json, settings.json veya projects bulunan ~/.claude-work gibi bir CLAUDE_CONFIG_DIR klasörü seçin. Klasör size ait olmalı, başkaları yazamamalı ve .claude.json bir bağlantı olmamalıdır.",
            signIn: "Bu klasörle Claude Code’da /login komutunu çalıştırın.",
            update: "Sınırları denetlemek için Claude Code’u güncelleyin.",
            missing: "Sınırları denetlemek için Claude Code’u yükleyin.")
        case .ru: return ClaudeAccountStrings(
            title: "Аккаунты Claude",
            explanation: "Каждая добавленная папка CLAUDE_CONFIG_DIR получает собственную карточку лимитов. Пока открыта страница «ИИ-агенты», Claude Code проверяет каждую примерно раз в пять минут со входом этой папки. Запросы не отправляются. Сеансы, запущенные в Терминале с любой папкой ~/.claude-<имя>, отображаются как активные с названием аккаунта.",
            fallback: "Без добавленных аккаунтов лимиты Claude берутся из обычной папки Claude Code и приложения Claude.",
            chooseFolder: "Выберите папку Claude Code",
            invalidFolder: "Выберите папку CLAUDE_CONFIG_DIR, например ~/.claude-work, в которой есть .claude.json, settings.json или projects. Папка должна принадлежать вам и быть недоступной для записи другим, а .claude.json не должен быть ссылкой.",
            signIn: "Выполните /login в Claude Code с этой папкой.",
            update: "Обновите Claude Code, чтобы проверить лимиты.",
            missing: "Установите Claude Code, чтобы проверить лимиты.")
        case .es: return ClaudeAccountStrings(
            title: "Cuentas de Claude",
            explanation: "Cada carpeta CLAUDE_CONFIG_DIR que añadas tiene su propia tarjeta de límites. Mientras la página Agentes de IA está abierta, Claude Code comprueba cada una cada cinco minutos aproximadamente con el inicio de sesión de esa carpeta. No se envía ningún prompt. Las sesiones que se ejecutan en Terminal con cualquier carpeta ~/.claude-<nombre> aparecen como activas, con el nombre de su cuenta.",
            fallback: "Sin cuentas añadidas, los límites de Claude vienen de la carpeta habitual de Claude Code y de la app Claude.",
            chooseFolder: "Elige una carpeta de Claude Code",
            invalidFolder: "Elige una carpeta CLAUDE_CONFIG_DIR, como ~/.claude-work, que contenga .claude.json, settings.json o projects. La carpeta debe ser tuya y no tener permiso de escritura para otros, y .claude.json no puede ser un enlace.",
            signIn: "Ejecuta /login en Claude Code con esta carpeta.",
            update: "Actualiza Claude Code para comprobar los límites.",
            missing: "Instala Claude Code para comprobar los límites.")
        case .sk: return ClaudeAccountStrings(
            title: "Účty Claude",
            explanation: "Každý pridaný priečinok CLAUDE_CONFIG_DIR dostane vlastnú kartu limitov. Kým je otvorená stránka AI agenti, Claude Code každý z nich približne každých päť minút skontroluje s prihlásením daného priečinka. Neodosiela sa žiadna výzva. Relácie spustené v Termináli s ktorýmkoľvek priečinkom ~/.claude-<názov> sa zobrazia ako aktívne s názvom účtu.",
            fallback: "Bez pridaných účtov pochádzajú limity Claude z bežného priečinka Claude Code a z aplikácie Claude.",
            chooseFolder: "Vyberte priečinok Claude Code",
            invalidFolder: "Vyberte priečinok CLAUDE_CONFIG_DIR, napríklad ~/.claude-work, v ktorom je .claude.json, settings.json alebo projects. Priečinok musí patriť vám a ostatní doň nesmú zapisovať, a .claude.json nesmie byť odkaz.",
            signIn: "Spustite /login v Claude Code s týmto priečinkom.",
            update: "Ak chcete skontrolovať limity, aktualizujte Claude Code.",
            missing: "Ak chcete skontrolovať limity, nainštalujte Claude Code.")
        case .de: return ClaudeAccountStrings(
            title: "Claude-Konten",
            explanation: "Jeder hinzugefügte CLAUDE_CONFIG_DIR-Ordner erhält eine eigene Limitkarte. Solange die Seite KI-Agenten geöffnet ist, prüft Claude Code jeden etwa alle fünf Minuten mit der Anmeldung dieses Ordners. Es wird kein Prompt gesendet. Sitzungen, die im Terminal mit einem beliebigen ~/.claude-<Name>-Ordner laufen, erscheinen als aktiv, mit dem Namen ihres Kontos.",
            fallback: "Ohne hinzugefügte Konten stammen die Claude-Limits aus dem üblichen Ordner von Claude Code und aus der Claude-App.",
            chooseFolder: "Claude-Code-Ordner auswählen",
            invalidFolder: "Wähle einen CLAUDE_CONFIG_DIR-Ordner wie ~/.claude-work, der .claude.json, settings.json oder projects enthält. Der Ordner muss dir gehören und darf für andere nicht beschreibbar sein, und .claude.json darf kein Link sein.",
            signIn: "Führe /login in Claude Code mit diesem Ordner aus.",
            update: "Aktualisiere Claude Code, um die Limits zu prüfen.",
            missing: "Installiere Claude Code, um die Limits zu prüfen.")
        case .fr: return ClaudeAccountStrings(
            title: "Comptes Claude",
            explanation: "Chaque dossier CLAUDE_CONFIG_DIR ajouté a sa propre carte de limites. Tant que la page Agents IA est ouverte, Claude Code vérifie chacun environ toutes les cinq minutes avec la connexion de ce dossier. Aucun prompt n’est envoyé. Les sessions lancées dans le Terminal avec un dossier ~/.claude-<nom> apparaissent comme actives, avec le nom de leur compte.",
            fallback: "Sans compte ajouté, les limites de Claude proviennent du dossier habituel de Claude Code et de l’app Claude.",
            chooseFolder: "Choisir un dossier Claude Code",
            invalidFolder: "Choisissez un dossier CLAUDE_CONFIG_DIR, comme ~/.claude-work, contenant .claude.json, settings.json ou projects. Le dossier doit vous appartenir et ne pas être modifiable par d’autres, et .claude.json ne doit pas être un lien.",
            signIn: "Exécutez /login dans Claude Code avec ce dossier.",
            update: "Mettez à jour Claude Code pour vérifier les limites.",
            missing: "Installez Claude Code pour vérifier les limites.")
        case .it: return ClaudeAccountStrings(
            title: "Account Claude",
            explanation: "Ogni cartella CLAUDE_CONFIG_DIR aggiunta ha la propria scheda dei limiti. Mentre la pagina Agenti IA è aperta, Claude Code controlla ciascuna circa ogni cinque minuti con l’accesso di quella cartella. Nessun prompt viene inviato. Le sessioni avviate nel Terminale con una qualsiasi cartella ~/.claude-<nome> risultano attive, con il nome del loro account.",
            fallback: "Senza account aggiunti, i limiti di Claude provengono dalla cartella abituale di Claude Code e dall’app Claude.",
            chooseFolder: "Scegli una cartella di Claude Code",
            invalidFolder: "Scegli una cartella CLAUDE_CONFIG_DIR, come ~/.claude-work, che contenga .claude.json, settings.json o projects. La cartella deve essere tua e non scrivibile da altri, e .claude.json non deve essere un collegamento.",
            signIn: "Esegui /login in Claude Code con questa cartella.",
            update: "Aggiorna Claude Code per controllare i limiti.",
            missing: "Installa Claude Code per controllare i limiti.")
        case .ja: return ClaudeAccountStrings(
            title: "Claude アカウント",
            explanation: "追加した CLAUDE_CONFIG_DIR フォルダごとに上限カードが表示されます。AI エージェントのページを開いている間、Claude Code が各フォルダのサインインで約 5 分ごとに確認します。プロンプトは送信されません。任意の ~/.claude-<名前> フォルダでターミナルから実行中のセッションは、アカウント名付きで作業中として表示されます。",
            fallback: "アカウントを追加しない場合、Claude の上限は Claude Code の通常のフォルダと Claude アプリから取得されます。",
            chooseFolder: "Claude Code のフォルダを選択",
            invalidFolder: ".claude.json、settings.json、projects のいずれかを含む ~/.claude-work などの CLAUDE_CONFIG_DIR フォルダを選択してください。フォルダは自分が所有し、他者が書き込めない必要があります。また .claude.json はリンクにできません。",
            signIn: "このフォルダで Claude Code の /login を実行してください。",
            update: "上限を確認するには Claude Code をアップデートしてください。",
            missing: "上限を確認するには Claude Code をインストールしてください。")
        case .ko: return ClaudeAccountStrings(
            title: "Claude 계정",
            explanation: "추가한 CLAUDE_CONFIG_DIR 폴더마다 자체 한도 카드가 표시됩니다. AI 에이전트 페이지가 열려 있는 동안 Claude Code가 각 폴더의 로그인으로 약 5분마다 확인합니다. 프롬프트는 전송되지 않습니다. ~/.claude-<이름> 폴더로 터미널에서 실행 중인 세션은 계정 이름과 함께 작업 중으로 표시됩니다.",
            fallback: "계정을 추가하지 않으면 Claude 한도는 Claude Code의 기본 폴더와 Claude 앱에서 가져옵니다.",
            chooseFolder: "Claude Code 폴더 선택",
            invalidFolder: ".claude.json, settings.json 또는 projects가 들어 있는 ~/.claude-work 같은 CLAUDE_CONFIG_DIR 폴더를 선택하세요. 폴더는 본인 소유여야 하고 다른 사용자가 쓸 수 없어야 하며, .claude.json은 링크일 수 없습니다.",
            signIn: "이 폴더로 Claude Code에서 /login을 실행하세요.",
            update: "한도를 확인하려면 Claude Code를 업데이트하세요.",
            missing: "한도를 확인하려면 Claude Code를 설치하세요.")
        case .uk: return ClaudeAccountStrings(
            title: "Облікові записи Claude",
            explanation: "Кожна додана папка CLAUDE_CONFIG_DIR отримує власну картку лімітів. Поки відкрита сторінка «ШІ-агенти», Claude Code перевіряє кожну приблизно раз на п’ять хвилин із входом цієї папки. Запити не надсилаються. Сеанси, запущені в Терміналі з будь-якою папкою ~/.claude-<назва>, відображаються як активні з назвою облікового запису.",
            fallback: "Без доданих облікових записів ліміти Claude беруться зі звичайної папки Claude Code і програми Claude.",
            chooseFolder: "Виберіть папку Claude Code",
            invalidFolder: "Виберіть папку CLAUDE_CONFIG_DIR, наприклад ~/.claude-work, у якій є .claude.json, settings.json або projects. Папка має належати вам і бути недоступною для запису іншим, а .claude.json не може бути посиланням.",
            signIn: "Виконайте /login у Claude Code з цією папкою.",
            update: "Оновіть Claude Code, щоб перевірити ліміти.",
            missing: "Установіть Claude Code, щоб перевірити ліміти.")
        case .zhHans: return ClaudeAccountStrings(
            title: "Claude 账户",
            explanation: "你添加的每个 CLAUDE_CONFIG_DIR 文件夹都有自己的额度卡片。AI 智能体页面打开期间，Claude Code 会使用该文件夹自己的登录，大约每五分钟检查一次。不会发送任何提示词。在“终端”中使用任一 ~/.claude-<名称> 文件夹运行的会话会显示为进行中，并标注其账户。",
            fallback: "未添加账户时，Claude 额度来自 Claude Code 的常用文件夹和 Claude App。",
            chooseFolder: "选择 Claude Code 文件夹",
            invalidFolder: "请选择包含 .claude.json、settings.json 或 projects 的 CLAUDE_CONFIG_DIR 文件夹，例如 ~/.claude-work。该文件夹必须归你所有且其他人不可写入，.claude.json 不能是链接。",
            signIn: "请在此文件夹下的 Claude Code 中运行 /login。",
            update: "请更新 Claude Code 以检查额度。",
            missing: "请安装 Claude Code 以检查额度。")
        case .zhTW: return ClaudeAccountStrings(
            title: "Claude 帳號",
            explanation: "你加入的每個 CLAUDE_CONFIG_DIR 資料夾都有自己的額度卡片。AI 代理頁面開啟期間，Claude Code 會使用該資料夾自己的登入，大約每五分鐘檢查一次。不會傳送任何提示詞。在「終端機」中使用任一 ~/.claude-<名稱> 資料夾執行的工作階段會顯示為進行中，並標示其帳號。",
            fallback: "未加入帳號時，Claude 額度來自 Claude Code 的常用資料夾和 Claude App。",
            chooseFolder: "選擇 Claude Code 資料夾",
            invalidFolder: "請選擇包含 .claude.json、settings.json 或 projects 的 CLAUDE_CONFIG_DIR 資料夾，例如 ~/.claude-work。該資料夾必須屬於你且他人無法寫入，.claude.json 不可為連結。",
            signIn: "請在此資料夾的 Claude Code 中執行 /login。",
            update: "請更新 Claude Code 以檢查額度。",
            missing: "請安裝 Claude Code 以檢查額度。")
        case .zhHK: return ClaudeAccountStrings(
            title: "Claude 帳戶",
            explanation: "你加入的每個 CLAUDE_CONFIG_DIR 資料夾都有自己的額度卡片。AI 代理頁面開啟期間，Claude Code 會使用該資料夾自己的登入，大約每五分鐘檢查一次。不會傳送任何提示詞。在「終端機」中使用任何 ~/.claude-<名稱> 資料夾執行的工作階段會顯示為進行中，並標示其帳戶。",
            fallback: "未加入帳戶時，Claude 額度來自 Claude Code 的常用資料夾和 Claude App。",
            chooseFolder: "選擇 Claude Code 資料夾",
            invalidFolder: "請選擇包含 .claude.json、settings.json 或 projects 的 CLAUDE_CONFIG_DIR 資料夾，例如 ~/.claude-work。該資料夾必須屬於你且其他人無法寫入，.claude.json 不可以是連結。",
            signIn: "請在此資料夾的 Claude Code 中執行 /login。",
            update: "請更新 Claude Code 以檢查額度。",
            missing: "請安裝 Claude Code 以檢查額度。")
        }
    }
}
