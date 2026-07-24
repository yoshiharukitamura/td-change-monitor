# TD Change Monitor

Treasure Dataのテーブル、Workflowプロジェクト、登録クエリの変更を日次で検出し、変更証跡をGitHubへpushし、重要変更をリソース単位でBacklogへ通知するWindowsバッチです。TDのテーブルレコード、実行結果、API生レスポンスは保存しません。

## 実装状況

- テーブル: 日次バッチ、Backlog、Git保存まで実装済み。
- Workflow: 安全なarchive展開、`.dig`・`.sql`差分、schedule差分、project単位のBacklog・Git保存まで実装済み。
- 登録クエリ: Query ID一覧・詳細・404、SQLと設定の差分、Backlog・Git保存まで実装済み。

## 構成

```text
Windowsタスクスケジューラ -> PowerShell -> uv/Python
  -> TD Query API: Audit Log
  -> TD Table API: 現在のschema
  -> TD Workflow API: project / archive / schedule
  -> TD Console API: 登録クエリ一覧 / 詳細
  -> Backlog API: 課題の検索・作成
  -> local Git: pull --ff-only / commit / push
```

本番はWindowsタスクスケジューラで動かし、WSL/Linuxは開発・検証だけに使います。

## 初期設定

前提はPython 3.11以上、uv、Gitです。ローカルリポジトリで、タスク実行ユーザーが`git pull`と`git push`できるようGit Credential ManagerまたはSSHを設定してください。

```powershell
Copy-Item .env.example .env
Copy-Item config\target_tables.example.yml config\target_tables.yml
Copy-Item config\resource_targets.example.yml config\resource_targets.yml
uv sync
```

`.env`へTD、Backlog、ローカルGitの設定を入れます。`GIT_REPOSITORY_PATH=.`ならこのリポジトリを使います。`GITHUB_REPOSITORY_URL`はBacklog本文のdiffリンク生成にだけ使います。

棚卸しExcelからWorkflow Project IDとQuery IDを実API照合して生成する場合は、次を実行します。0件または複数件一致の行は`needs_review`となり、ID確定まで監視から除外されます。

```powershell
uv run td-change-monitor --import-targets-from "C:\path\to\対象一覧.xlsx"
```

## 初回実行

監視開始時刻をUTCで決め、テーブル、Workflow、schedule、登録クエリの現行状態と単一stateを作ります。初回基準登録ではdiffとBacklog課題を作りません。

```powershell
uv run td-change-monitor --bootstrap --bootstrap-state-end-at "2026-07-13T00:00:00Z"
```

確認後に通常実行します。

```powershell
.\scripts\run_dry_run.ps1
.\scripts\run_td_change_monitor.ps1
```

dry-runはTDとローカルGitを読みますが、Backlog作成、commit、pushは行いません。

## タスク登録

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install_scheduled_task.ps1 -At "08:00"
Start-ScheduledTask -TaskName "TDChangeMonitor"
```

タスクは停止中の実行を復帰後に開始し、多重起動を抑止します。タスク実行ユーザーのGit認証が非対話で通ることを必ず手動確認してください。

## 保存データ

```text
schemas/current/{database}/{table}.json
workflows/current/{project_name}/
workflow_schedules/current/{project_name}.json
saved_queries/current/{query_id}.json
diffs/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.md
diffs/workflows/YYYY/MM/DD/{project_name}_{aggregated_change_id}.md
diffs/saved_queries/YYYY/MM/DD/{query_id}_{aggregated_change_id}.md
audit_events/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.json
state/state.json
logs/*.log  # Git対象外、既定30日
```

最新状態は同じファイルへ上書きします。変更なしの日次ファイル、全量snapshot、Audit全件、Workflow archive、APIレスポンス、TDレコード、登録クエリの実行結果は保存しません。過去状態はGit履歴から確認します。

## 容量管理

現在容量は読み取り専用スクリプトで確認できます。

```powershell
.\scripts\check_storage.ps1
```

概算式は次のとおりです。

```text
1年分 ~= 現行schema合計
       + 年間変更件数 x (平均diff + 平均Audit証跡)
       + Git履歴オーバーヘッド
       + 30日分のローカルログ
```

例として1日5テーブル変更、1変更あたりdiffとAudit合計20KiBなら、生ファイルは年間約36MiBです。Git履歴や現行schema、ログを含めても通常は100から200MiB程度ですが、実データは`check_storage.ps1`で継続確認してください。生成ファイル1件の既定上限は5MiBです。

## WSL / Linux検証

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
export UV_PROJECT_ENVIRONMENT=.venv-linux
uv sync
uv build
uv run ruff check .
uv run mypy src
uv run pytest
```

Linux cronは設定しません。

## 運用前の手動確認

- TD APIキーが`td_audit_log.access`をqueryでき、対象tableのmetadataを取得できること
- Backlogのproject、issue type、priority IDとAPIキー権限
- `config/target_tables.yml`の対象table一覧
- `config/resource_targets.yml`の`monitor`対象と`needs_review`対象
- タスク実行ユーザーで`git pull --ff-only`と`git push`が非対話で成功すること
- bootstrap開始時刻と初回通常実行のdry-run結果

詳しい処理は[仕様書](docs/SPEC.md)を参照してください。
