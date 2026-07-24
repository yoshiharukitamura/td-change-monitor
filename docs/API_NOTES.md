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

## Workflow

Workflow APIは`https://api-workflow.treasuredata.co.jp`をBase URLとして使用する。Postman確認済みの取得方法は次のとおり。

- プロジェクト詳細
- プロジェクト内Workflow一覧
- プロジェクトarchive
- schedule詳細
- プロジェクト内schedule一覧

schedule IDはWorkflow IDとは別のIDである。schedule詳細は`GET /api/schedules/{schedule_id}`、プロジェクト内schedule一覧は`GET /api/projects/{project_id}/schedules`で取得する。

確認済みscheduleレスポンスには周期、固定実行時刻、timezoneが含まれず、`nextRunTime`と`nextScheduleTime`だけが含まれる。次回日時から固定scheduleを逆算してはいけない。固定設定はDigdagの定義仕様に従い、対応する`.dig`のトップレベル`timezone:`と`schedule:`から取得する。schedule APIはschedule ID、対象Workflow、有効・無効に使用する。

取得済みの実Workflow archiveを安全展開処理で検証した。通常ファイル32件、symlink・hardlink・危険パス0件で、`.dig` 8件、`.sql` 23件、`.yml` 1件だった。監視対象31件はすべてUTF-8として読み取れ、一時展開ディレクトリは処理後に削除できた。`.yml`は未承認のため監視対象外とする。

scheduleを持つ実projectでもWorkflow名と同名の`.dig`を対応付けられることをdry-runで確認した。block mapping形式に加え、`schedule: {"daily>": "10:00:00", ...}`形式のinline mappingが実在したため両方を正規化する。

## 登録クエリ

Postmanで`GET /v3/schedule/list`のレスポンス構造を確認した。確認した911件には、各要素に次の13項目があった。

- `name`
- `cron`
- `timezone`
- `delay`
- `created_at`
- `type`
- `query`
- `database`
- `user_name`
- `priority`
- `retry_limit`
- `result`
- `next_time`

`id`、`query_id`、`queryId`、`schedule_id`のいずれも含まれていなかった。このため、このAPIだけでは要件であるQuery IDによる登録クエリの追跡を実現できない。

レスポンスにはSQL本文と出力先設定が含まれるため、生レスポンスはfixtureやGitへ保存しない。項目名、件数、ID項目の有無だけを`tests/fixtures/saved_query_list_response_summary.json`へ記録する。

Query IDを含むTD Console一覧APIを後続確認できたため、`GET /v3/schedule/list`は登録クエリ監視には使用しない。

TD Consoleの登録クエリ編集画面では、次の詳細APIが使用されていた。

- `GET https://console.treasuredata.co.jp/v4/queries/{query_id}`
- ブラウザセッション認証で200を確認した。
- URLのQuery IDとレスポンスの`id`が一致する。
- `queryString`、`name`、`database`、`type`、`engineVersion`、`connectorConfig`、`cron`、`timeZone`、`delay`、`priority`、`retryLimit`を取得できる。
- `user`から所有者IDと名前を取得できる。
- `nextRunAt`、`lastJob`、`permissions`などの実行時・閲覧者依存情報も含まれる。

このレスポンスにより、Query IDを主キーとした現在状態の取得は可能と判断できる。さらに、PostmanでCookieを設定せず、TD APIキーを`Authorization: TD1 ...`で指定して同じ詳細JSONを取得できた。日次バッチはブラウザセッションを使用せず、TD APIキーでこのAPIを呼び出す。

詳細レスポンスにはSQL本文と利用者情報が含まれるため、生レスポンスは保存しない。確認した項目構造だけを`tests/fixtures/saved_query_detail_response_summary.json`へ記録する。

出力設定がある登録クエリの詳細APIをTD APIキーで取得し、200と非nullの`connectorConfig`オブジェクトを確認した。出力設定値は秘密情報を含む可能性があるため、そのままGit成果物やログへ保存しない。変更検知で使用する場合は、保存可能な項目へ正規化するか、値を保持しないハッシュとして扱う。

存在しないQuery IDで詳細APIを呼ぶとHTTP 404になり、レスポンスには`message`と`statusCode`が含まれた。`message`は登録クエリではなく`Schedule with id ... not found`という文言だったため、削除判定はメッセージではなくHTTPステータスだけを使用する。

初回マスター生成とQuery ID未記載行の照合には、次のQuery ID付き一覧APIを使用する。

TD Consoleの登録クエリ一覧画面では、次のページングAPIが使用されていた。

- `GET https://console.treasuredata.co.jp/v4/queries/paginated_index`
- 初回query parameterは`minimalConnectorConfig=true`。
- レスポンス最上位は`queries`と`pagination`。
- `queries`の各要素からQuery ID、名前、database、所有者、エンジン、固定schedule設定を取得できる。
- 一覧要素には`queryString`がないため、SQL本文は詳細APIから取得する。
- `pagination`には`hasNextPage`、`nextPage`、`queriesFound`、`availableAnchors`がある。
- `nextPage`は次ページの相対URLで、`anchor_column`、`anchor_id`、`anchor_value`、`locale`、`page_size`、`sort_direction`を含む。

この一覧にQuery IDがあるため、初回マスター生成時はExcelのクエリ名、database、所有者と照合し、一意に一致した行へQuery IDを設定できる。0件または複数件一致は`needs_review`とする。

実一覧には`database`または`user`がnullで、Excelの照合キーを作れない項目が含まれる場合がある。この項目だけは初回一覧照合から除外する。ID確定後の個別詳細APIでは両項目を必須として検証する。

`nextPage`のquery parameterには実際のクエリ名が含まれる場合があるため、URL全体をログへ出さない。初回レスポンスでは911件と報告されたが、件数は実行時に変わるためコードへ固定しない。

ブラウザセッションと、Cookieを使用しないTD APIキー認証の両方で一覧の200レスポンスを確認した。返された`nextPage`による2ページ目も取得できた。確認した2ページは各25件で、ページ内のQuery IDは一意、ページ間のQuery ID重複は0件、先頭Query IDも異なっていた。

確認した50件のうち、`connectorConfig`が非nullの登録クエリは6件、`cron`が非nullの登録クエリは2件だった。`connectorConfig`は`id`と`connector`を持ち、`connector`は`id`、`name`、`type`を持つ。実際のID・名前・設定値は保存しない。

## Backlog

APIキーをquery parameterとして送るが、URL、例外、ログへキーを出さない。`aggregated_change_id`で既存課題を検索してから必要時だけ作成する。

## Git連携

Git remoteに対してローカルGitで`pull --ff-only`、`commit`、`push`する。`GITHUB_REPOSITORY_URL`はBacklog本文へ載せるblob URLの組み立てに使用する。
