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
- [x] schema、diff、Audit、state以外を自動stageしない。
- [x] APIキー、token、Authorization headerを成果物へ保存しない。
- [x] 複数テーブルの変更を1実行1コミットにまとめる。
- [x] 同じ論理テーブルの複数操作をBacklog課題1件にまとめる。
- [x] ローカルGitのpull、commit、pushを実リポジトリで検証する。

## 品質ゲート

```powershell
uv run ruff check .
uv run mypy src
uv run pytest
```

- [x] PowerShell全スクリプトの構文解析が成功する。
- [ ] WSL/Linuxで`uv sync`、`uv build`、ruff、mypy、pytestが成功する。
- [x] `scripts/check_storage.ps1`が容量を表示し、ファイルを変更しない。

## 運用前の手動確認

- [ ] TD本番APIキーで`td_audit_log.access`をqueryできる。
- [ ] 対象tableすべてでTable APIの`id`と`schema`を取得できる。
- [ ] Backlogのproject、issue type、priority IDと権限が正しい。
- [ ] タスク実行ユーザーでGit認証が非対話で成功する。
- [ ] `config/target_tables.yml`を業務担当者が確認した。
- [ ] bootstrap開始時刻を確定した。
- [ ] dry-runログに秘密情報やTDレコードがない。
- [ ] テスト変更1件でBacklog本文とGitHub diffリンクを目視確認した。
