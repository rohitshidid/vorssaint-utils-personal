// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's page of Docker containers and Ollama models. "Docker" and
/// "Ollama" are product names and stay as they are in every language.
struct NotchWorkloadStrings {
    let title: String
    let description: String
    let notInstalled: String
    let dockerStopped: String
    let ollamaStopped: String
    let noContainers: String
    let noModels: String
    let stopContainer: String
    let unloadModel: String
    let confirmStopFormat: String
    let confirmStopMessage: String
    let stop: String
    let unloadsInFormat: String
    let staysLoaded: String

    func confirmStop(_ name: String) -> String { String(format: confirmStopFormat, name) }
    func unloadsIn(_ time: String) -> String { String(format: unloadsInFormat, time) }
}

extension FeatureStrings {
    static func notchWorkloads(_ language: AppLanguage) -> NotchWorkloadStrings {
        switch language {
        case .enUS: return NotchWorkloadStrings(
            title: "Docker & Ollama",
            description: "Running Docker containers and loaded Ollama models in the island, with the memory each one uses and a button to stop it.",
            notInstalled: "Docker and Ollama aren’t installed on this Mac.",
            dockerStopped: "Docker isn’t running",
            ollamaStopped: "Ollama isn’t running",
            noContainers: "No containers running",
            noModels: "No models loaded",
            stopContainer: "Stop container",
            unloadModel: "Unload from memory",
            confirmStopFormat: "Stop %@?",
            confirmStopMessage: "Docker stops the container and keeps its data. You can start it again from Docker.",
            stop: "Stop",
            unloadsInFormat: "Unloads in %@",
            staysLoaded: "Stays loaded")
        case .ptBR: return NotchWorkloadStrings(
            title: "Docker e Ollama",
            description: "Contêineres do Docker em execução e modelos do Ollama carregados na ilha, com a memória que cada um usa e um botão para pará-lo.",
            notInstalled: "O Docker e o Ollama não estão instalados neste Mac.",
            dockerStopped: "O Docker não está em execução",
            ollamaStopped: "O Ollama não está em execução",
            noContainers: "Nenhum contêiner em execução",
            noModels: "Nenhum modelo carregado",
            stopContainer: "Parar contêiner",
            unloadModel: "Descarregar da memória",
            confirmStopFormat: "Parar %@?",
            confirmStopMessage: "O Docker para o contêiner e mantém os dados dele. Você pode iniciá-lo de novo pelo Docker.",
            stop: "Parar",
            unloadsInFormat: "Descarrega em %@",
            staysLoaded: "Fica carregado")
        case .tr: return NotchWorkloadStrings(
            title: "Docker ve Ollama",
            description: "Çalışan Docker kapsayıcıları ve yüklü Ollama modelleri adada; her birinin kullandığı bellek ve durdurma düğmesiyle.",
            notInstalled: "Bu Mac’te Docker ve Ollama yüklü değil.",
            dockerStopped: "Docker çalışmıyor",
            ollamaStopped: "Ollama çalışmıyor",
            noContainers: "Çalışan kapsayıcı yok",
            noModels: "Yüklü model yok",
            stopContainer: "Kapsayıcıyı durdur",
            unloadModel: "Bellekten kaldır",
            confirmStopFormat: "%@ durdurulsun mu?",
            confirmStopMessage: "Docker kapsayıcıyı durdurur ve verilerini korur. Docker’dan yeniden başlatabilirsiniz.",
            stop: "Durdur",
            unloadsInFormat: "%@ sonra kaldırılır",
            staysLoaded: "Yüklü kalır")
        case .ru: return NotchWorkloadStrings(
            title: "Docker и Ollama",
            description: "Запущенные контейнеры Docker и загруженные модели Ollama на острове: сколько памяти занимает каждый и кнопка остановки.",
            notInstalled: "Docker и Ollama не установлены на этом Mac.",
            dockerStopped: "Docker не запущен",
            ollamaStopped: "Ollama не запущена",
            noContainers: "Нет запущенных контейнеров",
            noModels: "Нет загруженных моделей",
            stopContainer: "Остановить контейнер",
            unloadModel: "Выгрузить из памяти",
            confirmStopFormat: "Остановить %@?",
            confirmStopMessage: "Docker остановит контейнер и сохранит его данные. Запустить его снова можно в Docker.",
            stop: "Остановить",
            unloadsInFormat: "Выгрузится через %@",
            staysLoaded: "Остаётся в памяти")
        case .es: return NotchWorkloadStrings(
            title: "Docker y Ollama",
            description: "Contenedores de Docker en ejecución y modelos de Ollama cargados en la isla, con la memoria que usa cada uno y un botón para detenerlo.",
            notInstalled: "Docker y Ollama no están instalados en este Mac.",
            dockerStopped: "Docker no está en ejecución",
            ollamaStopped: "Ollama no está en ejecución",
            noContainers: "Ningún contenedor en ejecución",
            noModels: "Ningún modelo cargado",
            stopContainer: "Detener contenedor",
            unloadModel: "Descargar de la memoria",
            confirmStopFormat: "¿Detener %@?",
            confirmStopMessage: "Docker detiene el contenedor y conserva sus datos. Puedes volver a iniciarlo desde Docker.",
            stop: "Detener",
            unloadsInFormat: "Se descarga en %@",
            staysLoaded: "Sigue cargado")
        case .sk: return NotchWorkloadStrings(
            title: "Docker a Ollama",
            description: "Spustené kontajnery Docker a načítané modely Ollama na ostrove s pamäťou, ktorú každý používa, a tlačidlom na zastavenie.",
            notInstalled: "Docker ani Ollama nie sú na tomto Macu nainštalované.",
            dockerStopped: "Docker nie je spustený",
            ollamaStopped: "Ollama nie je spustená",
            noContainers: "Žiadne spustené kontajnery",
            noModels: "Žiadne načítané modely",
            stopContainer: "Zastaviť kontajner",
            unloadModel: "Uvoľniť z pamäte",
            confirmStopFormat: "Zastaviť %@?",
            confirmStopMessage: "Docker kontajner zastaví a ponechá jeho dáta. Znova ho môžete spustiť v Dockeri.",
            stop: "Zastaviť",
            unloadsInFormat: "Uvoľní sa o %@",
            staysLoaded: "Zostáva načítaný")
        case .de: return NotchWorkloadStrings(
            title: "Docker & Ollama",
            description: "Laufende Docker-Container und geladene Ollama-Modelle auf der Insel, mit dem Speicher, den jedes belegt, und einer Taste zum Stoppen.",
            notInstalled: "Docker und Ollama sind auf diesem Mac nicht installiert.",
            dockerStopped: "Docker läuft nicht",
            ollamaStopped: "Ollama läuft nicht",
            noContainers: "Keine Container aktiv",
            noModels: "Keine Modelle geladen",
            stopContainer: "Container stoppen",
            unloadModel: "Aus dem Speicher entladen",
            confirmStopFormat: "%@ stoppen?",
            confirmStopMessage: "Docker stoppt den Container und behält seine Daten. Du kannst ihn in Docker wieder starten.",
            stop: "Stoppen",
            unloadsInFormat: "Wird in %@ entladen",
            staysLoaded: "Bleibt geladen")
        case .fr: return NotchWorkloadStrings(
            title: "Docker et Ollama",
            description: "Les conteneurs Docker en cours d’exécution et les modèles Ollama chargés sur l’île, avec la mémoire utilisée par chacun et un bouton pour l’arrêter.",
            notInstalled: "Docker et Ollama ne sont pas installés sur ce Mac.",
            dockerStopped: "Docker n’est pas lancé",
            ollamaStopped: "Ollama n’est pas lancé",
            noContainers: "Aucun conteneur en cours",
            noModels: "Aucun modèle chargé",
            stopContainer: "Arrêter le conteneur",
            unloadModel: "Décharger de la mémoire",
            confirmStopFormat: "Arrêter %@ ?",
            confirmStopMessage: "Docker arrête le conteneur et conserve ses données. Vous pourrez le relancer depuis Docker.",
            stop: "Arrêter",
            unloadsInFormat: "Déchargé dans %@",
            staysLoaded: "Reste chargé")
        case .it: return NotchWorkloadStrings(
            title: "Docker e Ollama",
            description: "I container Docker in esecuzione e i modelli Ollama caricati sull’isola, con la memoria usata da ciascuno e un pulsante per fermarlo.",
            notInstalled: "Docker e Ollama non sono installati su questo Mac.",
            dockerStopped: "Docker non è in esecuzione",
            ollamaStopped: "Ollama non è in esecuzione",
            noContainers: "Nessun container in esecuzione",
            noModels: "Nessun modello caricato",
            stopContainer: "Ferma container",
            unloadModel: "Scarica dalla memoria",
            confirmStopFormat: "Fermare %@?",
            confirmStopMessage: "Docker ferma il container e ne conserva i dati. Puoi riavviarlo da Docker.",
            stop: "Ferma",
            unloadsInFormat: "Scaricato tra %@",
            staysLoaded: "Resta caricato")
        case .ja: return NotchWorkloadStrings(
            title: "Docker と Ollama",
            description: "実行中の Docker コンテナと読み込まれた Ollama モデルをアイランドに表示し、それぞれのメモリ使用量と停止ボタンを示します。",
            notInstalled: "この Mac には Docker も Ollama もインストールされていません。",
            dockerStopped: "Docker は起動していません",
            ollamaStopped: "Ollama は起動していません",
            noContainers: "実行中のコンテナはありません",
            noModels: "読み込まれたモデルはありません",
            stopContainer: "コンテナを停止",
            unloadModel: "メモリから解放",
            confirmStopFormat: "%@ を停止しますか？",
            confirmStopMessage: "Docker はコンテナを停止し、データは残します。Docker からもう一度起動できます。",
            stop: "停止",
            unloadsInFormat: "%@ 後に解放",
            staysLoaded: "読み込んだまま")
        case .ko: return NotchWorkloadStrings(
            title: "Docker 및 Ollama",
            description: "실행 중인 Docker 컨테이너와 로드된 Ollama 모델을 아일랜드에 표시하고, 각각이 사용하는 메모리와 중지 버튼을 보여 줍니다.",
            notInstalled: "이 Mac에 Docker와 Ollama가 설치되어 있지 않습니다.",
            dockerStopped: "Docker가 실행 중이 아님",
            ollamaStopped: "Ollama가 실행 중이 아님",
            noContainers: "실행 중인 컨테이너 없음",
            noModels: "로드된 모델 없음",
            stopContainer: "컨테이너 중지",
            unloadModel: "메모리에서 해제",
            confirmStopFormat: "%@ 을(를) 중지하겠습니까?",
            confirmStopMessage: "Docker가 컨테이너를 중지하고 데이터는 유지합니다. Docker에서 다시 시작할 수 있습니다.",
            stop: "중지",
            unloadsInFormat: "%@ 후 해제",
            staysLoaded: "계속 로드됨")
        case .uk: return NotchWorkloadStrings(
            title: "Docker і Ollama",
            description: "Запущені контейнери Docker і завантажені моделі Ollama на острові: скільки пам’яті займає кожен і кнопка зупинки.",
            notInstalled: "Docker і Ollama не встановлено на цьому Mac.",
            dockerStopped: "Docker не запущено",
            ollamaStopped: "Ollama не запущено",
            noContainers: "Немає запущених контейнерів",
            noModels: "Немає завантажених моделей",
            stopContainer: "Зупинити контейнер",
            unloadModel: "Вивантажити з пам’яті",
            confirmStopFormat: "Зупинити %@?",
            confirmStopMessage: "Docker зупинить контейнер і збереже його дані. Запустити його знову можна в Docker.",
            stop: "Зупинити",
            unloadsInFormat: "Вивантажиться через %@",
            staysLoaded: "Лишається в пам’яті")
        case .zhHans: return NotchWorkloadStrings(
            title: "Docker 和 Ollama",
            description: "在灵动岛中显示正在运行的 Docker 容器和已载入的 Ollama 模型，以及各自占用的内存和停止按钮。",
            notInstalled: "这台 Mac 上没有安装 Docker 和 Ollama。",
            dockerStopped: "Docker 未运行",
            ollamaStopped: "Ollama 未运行",
            noContainers: "没有正在运行的容器",
            noModels: "没有已载入的模型",
            stopContainer: "停止容器",
            unloadModel: "从内存中卸载",
            confirmStopFormat: "停止“%@”？",
            confirmStopMessage: "Docker 会停止容器并保留其数据。你可以在 Docker 中再次启动它。",
            stop: "停止",
            unloadsInFormat: "%@后卸载",
            staysLoaded: "保持载入")
        case .zhTW: return NotchWorkloadStrings(
            title: "Docker 和 Ollama",
            description: "在動態島中顯示正在執行的 Docker 容器和已載入的 Ollama 模型，以及各自使用的記憶體和停止按鈕。",
            notInstalled: "這部 Mac 沒有安裝 Docker 和 Ollama。",
            dockerStopped: "Docker 未在執行",
            ollamaStopped: "Ollama 未在執行",
            noContainers: "沒有正在執行的容器",
            noModels: "沒有已載入的模型",
            stopContainer: "停止容器",
            unloadModel: "從記憶體卸載",
            confirmStopFormat: "要停止「%@」嗎？",
            confirmStopMessage: "Docker 會停止容器並保留其資料。你可以在 Docker 中再次啟動它。",
            stop: "停止",
            unloadsInFormat: "%@後卸載",
            staysLoaded: "保持載入")
        case .zhHK: return NotchWorkloadStrings(
            title: "Docker 和 Ollama",
            description: "在動態島中顯示正在執行的 Docker 容器和已載入的 Ollama 模型，以及各自使用的記憶體和停止按鈕。",
            notInstalled: "這部 Mac 沒有安裝 Docker 和 Ollama。",
            dockerStopped: "Docker 未在執行",
            ollamaStopped: "Ollama 未在執行",
            noContainers: "沒有正在執行的容器",
            noModels: "沒有已載入的模型",
            stopContainer: "停止容器",
            unloadModel: "從記憶體卸載",
            confirmStopFormat: "要停止「%@」嗎？",
            confirmStopMessage: "Docker 會停止容器並保留其資料。你可以在 Docker 中再次啟動它。",
            stop: "停止",
            unloadsInFormat: "%@後卸載",
            staysLoaded: "保持載入")
        }
    }
}
