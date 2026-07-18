# Codex実装プロンプト

Treasure Dataのテーブル変更をWindowsローカルPCで日次監視し、ローカルGitリポジトリからGitHubへpushし、必要な変更だけをBacklogへ通知するバッチを保守する。

## 実行基盤

```text
Windowsタスクスケジューラ
  -> PowerShell
  -> uv / Python
  -> Treasure Data API
  -> Backlog API
  -> local git pull / commit / push
```

GitHub API、OCI、GitHub Actions、Linux cronは使用しない。WSL/Linuxは開発と手動検証に限る。

## 処理フロー

1. 多重起動をロックで防ぐ。
2. ローカルGitリポジトリのbranchとstageを確認し、`git pull --ff-only`する。
3. `state/state.json`から前回のAudit取得終端と重複排除IDを読む。
4. Audit Logを`[前回終端-overlap, now-lag)`で取得する。
5. ID重複を除き、同じ論理テーブルのイベントをrename前後も含めて集約する。
6. 監視対象だけを選び、`schemas/current/`の前回状態とTable APIの現在状態を比較する。
7. 同じ論理テーブルの複数操作から最終Net Diffを作る。
8. 重要変更ならテーブル単位でBacklog課題を最大1件作る。本文へ操作者メール、操作履歴、GitHub diff URL、`aggregated_change_id`を載せる。
9. 最新スキーマ、diff、使用した最小Auditイベント、単一stateだけを明示パスでstageする。
10. 1コミットにまとめてpushする。途中失敗時は実行成功にしない。

## 保存契約

```text
schemas/current/{database}/{table}.json
diffs/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.md
audit_events/YYYY/MM/DD/{database}.{table}_{aggregated_change_id}.json
state/state.json
logs/td_change_monitor_YYYYMMDD_HHMMSS.log  # Git対象外
```

- TDテーブルのレコードを保存しない。
- Audit Queryの全結果や無関係イベントを保存しない。
- schema変更イベントの`old_value`/`new_value`は本文でなくSHA-256を保存する。
- 最新schemaは上書きし、過去状態はGit履歴で確認する。
- 変更なしの日はstate更新だけとし、diff、Audit、runファイルを作らない。
- `git add .`は禁止する。
- 生成ファイルは既定5MiBを超えたら停止する。
- ログは既定30日で削除する。

## 判定

Backlog対象は、カラム追加・削除・型変更、rename、delete、schema変更を伴う再作成。alias、順序、同一schemaでの再作成はGit証跡のみ。descriptionのみ、`include_v`のみ、`table_import_create`、件数・容量などのメタデータ変更は成果物対象外。

同じ実行内でrename、schema変更、deleteなどが重なった場合は、Audit履歴を1つにまとめ、現在状態を優先した最終表示とする。

## 検証

```powershell
uv run ruff check .
uv run mypy src
uv run pytest
```

PowerShell構文、WSLの`uv sync`、`uv build`、3検証コマンドも通す。秘密情報やTDレコードをfixture・ログ・成果物へ入れない。
