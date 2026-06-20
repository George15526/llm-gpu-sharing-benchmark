# Experiment Evidence

此資料夾保存本專案挑選後的實驗佐證資料。

## 目錄說明

| 路徑 | 說明 |
|---|---|
| `timeslicing/` | NVIDIA time-slicing baseline 的實驗佐證資料 |
| `hami/` | HAMi 實驗佐證資料 |
| `summary_index.tsv` | repeated experiment summary 索引 |
| `run_index.tsv` | 單次 run 輸出索引 |
| `environment_snapshot.txt` | 收集 evidence 當下的 Git / Kubernetes / NVIDIA 狀態快照，已做基本資訊遮蔽 |

## 收集原則

此資料夾僅放置可閱讀的實驗數據與佐證檔案，不重複複製專案內既有的 `scripts/`、`k8s/`、`docs/`。

實驗設計、環境說明、疑難排解與結果分析請參考 repo 根目錄的 `README.md` 與 `docs/`。

## Public-safe Redaction

可能包含機器資訊的檔案會進行基本遮蔽，例如：

- IP / endpoint
- Node name / hostname
- GPU UUID
- Container ID
- Kubernetes UID
- Host path / user path
- PID 或大型程序 ID

## 收集模式

本次 evidence 是依據 manifest 檔案挑選：

```text
evidence_manifest.txt
```

僅 manifest 內列出的 result directory 會被複製。

## 備註

預設不複製 raw request logs，例如 `requests.jsonl`，避免 repo 體積過大。
