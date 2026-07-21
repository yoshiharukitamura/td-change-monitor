# API確認メモ

## Treasure Data

Audit Logは`td_audit_log.access`をQuery APIで検索する。取得列はID、時刻、event名、結果、resource ID/name、HTTP method/path、attribute、old/new value、user/source user、target resource nameに限定する。

Table APIは次を使用する。

- `GET /v3/table/show/{database}/{table}`
- `schema`はJSON文字列なので、レスポンスJSONを読んだ後にschema文字列をJSON parseする。
- `id`は文字列へ正規化する。
- 404は現在テーブルが存在しないことを示す。

Postman確認では`/v3/table/show/{database}/{table}`から`id`、`name`、`schema`を取得できた。誤って`/v3/table/show/{{database}}/{{table}}`の変数が展開されていない場合は404になる。

Audit履歴上、同一テーブルのpreview操作でtable IDが継続していた。delete後のcreateでIDが変わる場合は同名でも再作成された別の物理テーブルとして扱う。

## Backlog

APIキーをquery parameterとして送るが、URL、例外、ログへキーを出さない。`aggregated_change_id`で既存課題を検索してから必要時だけ作成する。

## Git連携

Git remoteに対してローカルGitで`pull --ff-only`、`commit`、`push`する。`GITHUB_REPOSITORY_URL`はBacklog本文へ載せるblob URLの組み立てに使用する。
