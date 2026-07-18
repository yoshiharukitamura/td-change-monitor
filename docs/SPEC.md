# TD Change Monitor 仕様書

## 1. 目的と範囲

対象テーブルの定義変更を1日1回監視し、必要最小限の証跡をGitHubへ保存し、重要変更をBacklogへ通知する。TDテーブルのレコード内容は扱わない。

本番実行基盤はWindowsタスクスケジューラとPowerShell。TDとBacklogはAPI、GitHubはローカルGitのremoteとして扱い、GitHub REST APIは使わない。

## 2. 時刻と再実行

- 内部時刻はUTC、人向け表示だけJST。
- Audit検索は半開区間`[start, end)`。
- `end = now - AUDIT_LOG_LAG_MINUTES`。
- `start = state.audit_query_to - AUDIT_LOG_OVERLAP_MINUTES`。
- 重複区間はAudit `id`で除外する。
- stateは単一の`state/state.json`とし、PC停止後は前回終端から再開する。
- Backlog処理、commit、pushのいずれかが失敗した実行を成功扱いしない。push失敗後に残ったローカルcommitは次回処理前にpushする。

## 3. Audit取得と集約

Query APIで`td_audit_log.access`の必要列だけを取得する。対象イベントは`table_create`、`table_modify`、`table_delete`。`table_import_create`は無視する。

取得後、次の順に処理する。

1. 処理済みAudit IDを除外する。
2. Audit eventからdatabase、table、previous table、resource IDを解決する。
3. 同一`resource_id`、同一名、rename前後の連鎖を同じ論理テーブルへまとめる。
4. `config/target_tables.yml`の旧名または新名が許可対象なら処理対象にする。
5. 同じ論理テーブルの全イベントを時系列順に保持する。

解決不能なイベントが1件でもあればstateを更新せず失敗する。

## 4. 差分判定

前回状態は`schemas/current/{database}/{table}.json`、現在状態は`GET /v3/table/show/{database}/{table}`から得る。Table APIの`schema` JSON文字列を正規化し、`name/type/alias/description/position`を比較する。

差分項目は`added_columns`、`removed_columns`、`type_changes`、`alias_changes`、`description_changes`、`order_changes`。

複数操作がある場合はイベントごとの表示を単純に課題化せず、前回状態と現在状態から最終Net Diffを作る。現在テーブルが存在しなければdeleteを最優先し、renameとschema差分があれば複合変更にする。

| change_kind | 条件 | Backlog |
|---|---|---|
| `schema_change` | schemaに実差分 | 追加・削除・型変更なら作成 |
| `table_rename` | 名前変更のみ | 作成 |
| `table_rename_schema_change` | 名前とschema変更 | 作成 |
| `table_delete` | 現在存在しない | 作成 |
| `table_recreate` | table ID変更、schema同一 | Git証跡のみ |
| `table_recreate_schema_change` | table ID変更、schema変更 | 作成 |

descriptionのみ、`include_v`のみ、件数・容量・更新時刻などのmetadata変更、実差分0はdiff/Audit成果物も作らない。alias・順序だけはGit証跡を残すがBacklog課題は作らない。

## 5. aggregated_change_id

database、最終table名、Audit ID集合、前後schema hash、change kindから決定的なSHA-256を作る。実行時刻は材料にしない。同じ変更の再実行で同じIDになり、state対応表とBacklog検索で重複課題を防ぐ。

## 6. Backlog

同じ実行の同じ論理テーブルにつき最大1課題を作る。本文には次を含める。

- 対象tableとrename前のtable名
- 変更種別と最終Net Diff
- 変更したユーザーのメールアドレス
- 期間内の操作履歴
- GitHub上のdiff Markdown URL
- `aggregated_change_id`
- 使用したAudit Log ID

TDレコードやAudit生データへのリンクは載せない。既存IDが見つかれば課題を再作成しない。

## 7. Gitと保存契約

実行前にbranch、既存stageを確認し、`git pull --ff-only <remote> <branch>`する。自動生成対象だけを個別に`git add -A -- <path>`し、1実行1コミットでpushする。`git add .`、force push、履歴書き換え、自動gcは禁止。

```text
schemas/current/{database}/{table}.json
diffs/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.md
audit_events/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.json
state/state.json
```

`schemas/current`は上書きし、削除時は現行ファイルを削除する。履歴はGitで確認する。日付別全量schema、`schemas_deleted`、`net_diffs`、`runs`は作らない。

Audit成果物は対象論理テーブルの判定に使ったイベントだけをまとめ、schemaのold/new値はSHA-256だけを保存する。rawレスポンス、無関係イベント、TDレコードは保存しない。

各生成ファイルが`MAX_GENERATED_FILE_SIZE_MB`を超えたら、ファイル名とサイズだけをログへ出し、commit/pushせず失敗する。一時ファイルは成功・失敗の両方で削除する。

## 8. state

`state/state.json`は次を保持する。

- `last_successful_run_at`
- `audit_query_from`
- `audit_query_to`
- `processed_audit_event_ids`: IDから発生UTC時刻
- `processed_aggregated_change_ids`: IDから最終イベントUTC時刻
- `backlog_issues`: aggregated IDから課題キー
- `table_ids`: `database.table`から最新table ID

処理済みIDと課題対応は`PROCESSED_ID_RETENTION_DAYS`より古いものを削除し、無制限増加を防ぐ。

## 9. ログと容量

標準出力はJSON構造化ログとし、PowerShellが`logs/`へ保存する。ログはGit対象外で、開始時と終了時に`LOCAL_LOG_RETENTION_DAYS`より古い`.log`を削除する。既定30日。

`scripts/check_storage.ps1`は作業ツリー、`.git`、schema、diff、Audit、state、logsの容量を表示する。削除、gc、履歴変更はしない。
