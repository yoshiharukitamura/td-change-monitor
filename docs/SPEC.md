# TD Change Monitor 仕様書

## 1. 目的と範囲

対象テーブル、Workflowプロジェクトとschedule、登録クエリの変更を1日1回監視し、必要最小限の証跡をGitHubへ保存し、重要変更をBacklogへ通知する。TDテーブルのレコード、Workflowやクエリの実行結果は扱わない。

本番実行基盤はWindowsタスクスケジューラとPowerShell。TDとBacklogはAPI、GitHubはローカルGitのremoteとして扱う。

## 2. 時刻と再実行

- 内部時刻はUTC、人向け表示だけJST。
- Audit検索は半開区間`[start, end)`。
- `end = now - AUDIT_LOG_LAG_MINUTES`。
- `start = state.audit_query_to - AUDIT_LOG_OVERLAP_MINUTES`。
- 重複区間はAudit `id`で除外する。
- stateは単一の`state/state.json`とし、PC停止後は前回終端から再開する。
- Backlog処理、commit、pushのいずれかが失敗した実行を成功扱いしない。push失敗後に残ったローカルcommitは次回処理前にpushする。

監視対象は`config/target_tables.yml`と`config/resource_targets.yml`で管理する。棚卸しExcelの利用中行は専用CLIで実APIと照合し、Workflow Project IDとQuery IDを確定する。名前、database、ownerなどの照合結果が0件または複数件の場合は`needs_review`とし、安定IDが確定するまで日次監視から除外する。

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

同じ実行の同じ論理テーブル、Workflow project、Query IDにつき最大1課題を作る。本文には次を含める。

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
workflows/current/{project_name}/
workflow_schedules/current/{project_name}.json
saved_queries/current/{query_id}.json
diffs/YYYY/MM/DD/
diffs/workflows/
diffs/saved_queries/
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
- `workflow_project_names`: Project IDから最新project名

処理済みIDと課題対応は`PROCESSED_ID_RETENTION_DAYS`より古いものを削除し、無制限増加を防ぐ。

## 9. ログと容量

標準出力はJSON構造化ログとし、PowerShellが`logs/`へ保存する。ログはGit対象外で、開始時と終了時に`LOCAL_LOG_RETENTION_DAYS`より古い`.log`を削除する。既定30日。

`scripts/check_storage.ps1`は作業ツリー、`.git`、schema、diff、Audit、state、logsの容量を表示する。削除、gc、履歴変更はしない。

dry-runでは、検出した変更ごとに`td_change_monitor_dry_run_change`ログを出力する。テーブル名、変更種別、Backlog候補かどうか、Audit件数、カラム差分を含める。schema本文、APIレスポンス全体、秘密情報は含めない。

1実行で処理する変更テーブル数は`MAX_CHANGED_TABLES_PER_RUN`で制限し、既定値は250とする。上限を超えた場合はBacklog・Git・stateを更新せず失敗する。

## 10. Workflow API確認結果

Workflow APIは`TD_WORKFLOW_API_BASE_URL=https://api-workflow.treasuredata.co.jp`を使用する。実環境で次を確認済み。

- project詳細からproject ID、名前、revision、archiveMd5、archiveTypeを取得する。
- project archiveをgzipで取得する。
- project内Workflow一覧からWorkflow ID、名前、revision、timezoneを取得する。
- project内schedule一覧とschedule詳細からschedule ID、project、Workflow、有効・無効を取得する。
- 次回実行日時は毎回変化するため比較対象にしない。

projectのrevisionまたはarchiveMd5が前回と同じ場合はarchiveを取得しない。変更時だけ一時取得・展開し、`.dig`と`.sql`を比較する。archiveと展開ファイルは処理後に削除し、Gitへ保存しない。

Workflowのファイル変更とschedule変更はproject ID単位へ集約し、1回の実行で1プロジェクト最大1課題とする。

archive展開前に全memberを検証し、絶対パス、`..`、Windows予約名、重複パス、symlink、hardlink、特殊ファイル、サイズ上限超過を拒否する。監視対象ファイルはUTF-8として読めない場合も失敗させる。一時展開先を解決済みroot配下へ限定し、成功・失敗にかかわらず削除する。

WorkflowのGit保存内容は`.workflow_state.json`と対象`.dig`・`.sql`だけとする。metadataにはproject ID、名前、revision、archiveMd5、対象ファイルの相対パスとSHA-256を保存する。archive本体と監視対象外ファイルは保存しない。

ファイル差分は追加、削除、内容変更、renameへ分類する。同一内容hashの削除・追加を決定的にrenameとして対応付ける。改行コードだけをLFへ統一する。空白・改行だけ、または引用符外のコメントだけの内容変更はGit証跡を残すがBacklog通知対象にしない。

実archiveの初回棚卸しでは通常ファイル32件を確認した。内訳は`.dig` 8件、`.sql` 23件、`.yml` 1件だった。`.yml`は自動的に監視対象へ追加せず、追加要否が確認されるまで棚卸し情報だけを保持する。

## 11. Workflow scheduleの正規化と差分

schedule APIはschedule ID、所属project、対象Workflow、有効・無効の正本として使用する。周期・実行時刻・timezoneは、対象Workflow名と一意に対応する`.dig`のトップレベル`timezone:`と`schedule:`から取得する。timezoneが省略されている場合はDigdag仕様どおりUTCとする。

対応する`.dig`は、拡張子を除いたproject内相対pathがWorkflow名と一致するものを優先し、一致しない場合だけbasenameの一意一致を使用する。`schedule:`のblock mapping形式と、実環境で確認したinline mapping形式を扱う。inline mapping内の`start`や`skip_on_overtime`は固定周期ではないためsnapshotへ保存しない。0件または複数件、schedule定義なし、複数schedule演算子、未対応演算子、tab indentの場合は推測せず実行を失敗させる。

対応する固定schedule演算子は次の6種類とする。

- `hourly>`
- `daily>`
- `weekly>`
- `monthly>`
- `minutes_interval>`
- `cron>`

Gitへ保存する`workflow_schedules/current/{project_name}.json`は次の項目だけを持つ。

- project IDと名前
- schedule ID
- Workflow IDと名前
- 有効・無効
- schedule種別と固定値
- timezone
- 対応する`.dig`の相対path

`nextRunTime`と`nextScheduleTime`はAPIモデルにもGit snapshotにも含めない。前回と現在をschedule IDで比較し、追加、削除、有効・無効、対象Workflow、周期、時刻、timezone、定義pathの変更を検知する。schedule差分と`.dig`・`.sql`差分は同じ`WorkflowProjectDiff`へ統合し、Backlog候補はprojectごとに最大1件とする。

## 12. 登録クエリAPI確認結果

登録クエリは`TD_CONSOLE_API_BASE_URL=https://console.treasuredata.co.jp`を使用し、Cookieではなく`Authorization: TD1 ...`で取得する。実環境で次を確認済み。

- `GET /v4/queries/paginated_index?minimalConnectorConfig=true`: Query IDを含む一覧。
- `pagination.nextPage`: 次ページの相対URL。
- `GET /v4/queries/{query_id}`: SQL本文と現在設定を含む詳細。
- 存在しないQuery ID: HTTP 404。

一覧は`nextPage`がなくなるまで取得する。nextPageは同一Console APIの`/v4/queries/paginated_index`だけを許可し、外部URL、重複Query ID、循環nextPageをエラーにする。

## 13. 登録クエリの正規化と差分

登録クエリはQuery IDを主キーにし、名称変更後も同じリソースとして追跡する。Gitへ保存する現在状態は次に限定する。

- Query ID、クエリ名、SQL本文
- database IDと名前
- engine typeとversion
- connector typeとconnectorConfigのSHA-256
- cron、timezone、delay、priority、retry limit

`createdAt`、`updatedAt`、`nextRunAt`、`lastJob`、permissions、実行結果は保存・比較しない。connectorConfig原文は保存せず、変更検知用SHA-256へ変換後に破棄する。

前回snapshotと現在詳細を比較し、SQL、名称、database、engine、出力設定、固定schedule設定、削除を検知する。SQL本文は改行コードだけをLFへ統一し、その他の空白やコメントは変更しない。

同じQuery IDの複数変更は最終Net Diffへまとめ、1回の実行で1 Query ID最大1課題とする。初回は`saved_queries/current/{query_id}.json`へ基準状態を保存し、Backlog課題を作らない。
