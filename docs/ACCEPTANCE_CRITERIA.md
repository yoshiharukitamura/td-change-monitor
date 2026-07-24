# 受入条件

## 自動テスト

- [x] TDテーブルのレコード本体を保存しない。
- [x] Audit検索結果全体やevent.rawを保存しない。
- [x] 監視対象の判定に使った関連イベントだけをAudit成果物へ保存する。
- [x] 最新schemaを`schemas/current/`の同じファイルへ上書きする。
- [x] 日付別の全量schema snapshotを作らない。
- [x] 変更なしならdiff、Audit、runファイルを作らない。
- [x] 同じ論理テーブルの複数イベントを1つのAudit成果物へ集約する。
- [x] stateは`state/state.json`だけを使う。
- [x] 処理済みIDを保持日数で削除し、無制限に増やさない。
- [x] `logs/`と`*.log`をGit対象外にする。
- [x] 期限切れローカルログを削除するスクリプトを備える。
- [x] 原子的書込みの一時ファイルを正常時・失敗時に残さない。
- [x] 上限超過の生成ファイルをcommitしない。
- [x] `git add .`を使わない。
- [x] 許可したcurrent、diff、Audit、state以外を自動stageしない。
- [x] APIキー、token、Authorization headerを成果物へ保存しない。
- [x] 複数テーブルの変更を1実行1コミットにまとめる。
- [x] 同じ論理テーブルの複数操作をBacklog課題1件にまとめる。
- [x] ローカルGitのpull、commit、pushを実リポジトリで検証する。

## Workflow追加監視

- [x] project、Workflow、scheduleの実レスポンスを匿名fixture化している。
- [x] project revision、archiveMd5、archive、Workflow一覧を取得できる。
- [x] schedule ID、所属project、所属Workflow、有効・無効を取得できる。
- [x] 次回実行日時を正規化モデルへ含めない。
- [x] `.dig`から周期、固定実行時刻、timezoneを決定的に取得できる。
- [x] scheduleの追加・削除・有効無効・対象Workflow・固定設定を検知できる。
- [x] scheduleの正規化状態を動的実行日時なしでJSON保存・復元できる。
- [x] revisionとarchiveMd5が変更されていなければarchiveを取得しない。
- [x] `.dig`と`.sql`の追加・削除・変更・renameを検知できる。
- [x] 複数ファイル変更を1つのproject差分へ集約できる。
- [x] 空白・改行・コメントだけの内容変更をBacklog通知対象外にできる。
- [x] archiveの危険パス、link、重複、サイズ超過を拒否できる。
- [x] archiveと展開ファイルを処理後に削除できる。
- [x] archive全体と監視対象外拡張子をGit保存候補へ含めない。
- [x] Workflowファイル変更とschedule変更をproject単位の1課題候補へ集約できる。
- [x] scheduleを持つ実projectのarchiveでWorkflow名と`.dig`の対応を確認している。
- [x] block形式と実環境のinline mapping形式のscheduleを正規化できる。
- [x] Workflow project差分を日次サービス、Backlog、Git保存へ統合している。
- [ ] `.yml`を監視対象へ追加するか業務確認が完了している。

## 登録クエリ追加監視

- [x] TD APIキーでQuery ID付き一覧をページング取得できる。
- [x] TD APIキーでSQL本文を含む詳細を取得できる。
- [x] HTTP 404を削除済みとして扱える。
- [x] Query IDを主キーとして名称変更後も同じリソースとして比較できる。
- [x] SQL、名称、database、engine、出力設定、固定schedule設定を比較できる。
- [x] connectorConfig原文と認証情報をsnapshotへ保存しない。
- [x] 次回実行日時、最終Job、permissions、実行結果をsnapshotへ保存しない。
- [x] 同じ入力から決定的なresource change IDを作れる。
- [x] 初回基準登録でBacklog課題を作らない日次サービス統合がある。
- [x] 同じQuery IDの複数変更をBacklog課題1件へ集約できる。
- [x] `saved_queries/current/{query_id}.json`を明示stageしてpushできる。

## 品質ゲート

```powershell
uv run ruff check .
uv run mypy src
uv run pytest
```

- [x] PowerShell全スクリプトの構文解析が成功する。
- [x] WSL/Linuxで`uv sync`、`uv build`、ruff、mypy、pytestが成功する。
- [x] `scripts/check_storage.ps1`が容量を表示し、ファイルを変更しない。

## 運用前の手動確認

- [ ] TD本番APIキーで`td_audit_log.access`をqueryできる。
- [ ] 対象tableすべてでTable APIの`id`と`schema`を取得できる。
- [ ] Backlogのproject、issue type、priority IDと権限が正しい。
- [ ] タスク実行ユーザーでGit認証が非対話で成功する。
- [ ] `config/target_tables.yml`を業務担当者が確認した。
- [ ] `config/resource_targets.yml`の`needs_review`行を業務担当者が確認した。
- [ ] bootstrap開始時刻を確定した。
- [ ] dry-runログに秘密情報やTDレコードがない。
- [ ] テスト変更1件でBacklog本文とGitHub diffリンクを目視確認した。
