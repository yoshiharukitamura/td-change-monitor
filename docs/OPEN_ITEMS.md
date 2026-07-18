# 残作業と運用開始チェック

## 必須の手動作業

1. `.env`へ本番TD、Backlog、Git設定を入れる。
2. `config/target_tables.yml`へ確定した対象テーブル一覧を設定する。
3. タスク実行ユーザーで`git pull --ff-only origin main`と`git push origin main`を非対話実行できるようにする。
4. TD Audit Queryと対象Table APIをdry-runで確認する。
5. 監視開始UTC時刻を決めてbootstrapする。
6. 通常dry-run、通常実行、Backlog本文、GitHub diff URLを確認する。
7. タスクスケジューラへ登録し、手動起動テストを行う。

## 運用中の確認

- 毎週: タスクの終了コードと直近ログを確認する。
- 毎月: `scripts/check_storage.ps1`で作業ツリーと`.git`容量を確認する。
- 対象変更時: `config/target_tables.yml`をレビューする。
- 認証更新時: TD、Backlog、Gitの非対話アクセスを再確認する。

自動削除対象は期限切れローカルログと一時ファイルだけ。Git履歴の削除、force push、強制gcは手動でも通常運用では行わない。
