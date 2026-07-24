# Codex Working Rules

## 目的

WindowsローカルPCで日次実行し、Treasure Dataのテーブル、Workflowプロジェクト、登録クエリの変更を安全かつ再実行可能な形でローカルGitリポジトリ、GitHub、Backlogへ反映する。

## 絶対条件

1. 本番実行基盤はWindowsタスクスケジューラとPowerShell。
2. OCI、GitHub Actions、Linux cronは使用しない。WSL/Linuxは開発・検証用途のみ。
3. TDとBacklogはAPIで通信する。GitHubとの同期はローカルGitで`pull --ff-only`、`commit`、`push`する。
4. 秘密情報、TDテーブルのレコード、APIレスポンス全体をコード、Git、ログへ保存しない。
5. 内部時刻はUTC、人向け表示のみJST。
6. Audit Log取得期間は半開区間`[start, end)`とし、`end = now - AUDIT_LOG_LAG_MINUTES`とする。
7. Backlog処理、Gitコミット、Git pushが完了するまで実行成功としない。
8. `aggregated_change_id`でBacklog重複を防止する。
9. Git書き込みは1実行1コミット。`git add .`は禁止し、自動生成パスだけを明示的にstageする。
10. `table_modify`でも実スキーマ差分が0なら課題・diff・Audit成果物を作らない。
11. 同一実行内の同じ論理テーブルの操作は集約し、テーブルごとにBacklog課題を最大1件作る。
12. 多重起動を禁止し、PC停止後も`state/state.json`から未処理期間を再開する。
13. 最新スキーマは`schemas/current/`の1ファイルを上書きし、過去状態はGit履歴で確認する。
14. 変更時だけ`diffs/`と`audit_events/`へ成果物を作る。日次全量snapshot、日次runファイル、rawレスポンスは作らない。
15. state内の処理済みIDは`PROCESSED_ID_RETENTION_DAYS`で期限管理する。
16. ローカルログはGit対象外とし、`LOCAL_LOG_RETENTION_DAYS`経過後に削除する。
17. 生成ファイルが`MAX_GENERATED_FILE_SIZE_MB`を超えたらcommit/pushせず失敗させる。
18. Git履歴の書き換え、force push、自動`git gc`は行わない。
19. 監視対象はtable、Workflowプロジェクトとschedule、登録クエリだけとし、他のTDリソースへ広げない。
20. Workflowはproject ID、登録クエリはQuery IDを安定IDとして追跡する。
21. Workflow archiveは一時領域だけで扱い、登録クエリのconnectorConfig原文はGitやログへ保存しない。
22. 実環境で未確認のTD APIパス・項目を推測で本実装へ追加しない。

## Git管理対象

- `schemas/current/`
- `workflows/current/`
- `workflow_schedules/current/`
- `saved_queries/current/`
- `diffs/`
- `audit_events/`
- `state/state.json`

`logs/`、一時ファイル、`.env`、Workflow archive、APIの生レスポンスは管理対象外。

## 技術方針

- Python 3.11+
- uv
- httpx
- pydantic-settings + YAML
- tenacity
- pytest + respx
- ruff + mypy
- JSON構造化ログを標準出力し、PowerShellで`logs/`へ保存

## 完了条件

```powershell
uv run ruff check .
uv run mypy src
uv run pytest
```

PowerShell構文、WSL/Linux上の`uv build`とテストも確認する。
