---
tags:
  - type/handson
  - status/draft
---

# ハンズオン手順書：CoCo in Snowsight で Redshift 資産の移行から AI 分析までを効率よく進める

**対象**: SQL を書ける IT ご担当者（各自が自分のトライアル環境で操作）　**所要**: 本編 90 分（＋質疑・予備 30 分）
**環境**: Snowflake が事前に用意したトライアル環境。Snowsight だけで完結します（ローカルへのインストールは不要）
**データ**: すべて架空のデータです。実データ・機密情報は使いません
**配布物**: 本リポジトリ（GitHub 公開リポジトリ）に、手順書・変換元の Redshift SQL・セットアップ SQL をまとめています

```
.
├── README.md                 # 本手順書
├── redshift_assets/          # 変換元の Redshift 方言 SQL（第 1・2 幕で使用）
│   ├── rs_01_ddl.sql
│   ├── rs_02_mart.sql
│   ├── rs_03_procedure.sql
│   └── rs_04_dept_definitions.sql
└── sql/
    ├── 01_setup.sql          # セットアップ（準備で実行）
    └── 99_cleanup.sql        # 終了後の停止・削除
```

| 時間 | 内容 |
|---|---|
| 0〜10 分 | 0. 準備（リポジトリの取得とセットアップ） |
| 10〜30 分 | 第 1 幕：Redshift の SQL・DDL を Snowflake に変換して検証する |
| 30〜50 分 | 第 2 幕：部門ごとに違う「売上」の定義を 1 つにまとめる（Semantic View） |
| 50〜70 分 | 第 3 幕：ダッシュボードを作って公開する（タブ・ドリルダウン・連動フィルター） |
| 70〜90 分 | 第 4 幕：Agent を作り、CoWork で自然言語で質問する |

> 本手順の **プロンプトは例** です。CoCo の回答は毎回少しずつ変わります。画面の名称や位置は、実際の画面に合わせて読み替えてください。
> セットアップ SQL は配布物のため、そのまま実行して構いません。CoCo が生成した SQL は **実行前に必ず中身を読み**、意図しない `DROP` や `CREATE OR REPLACE` が含まれていないか確認してください。

---

## 0. 準備（〜10分）

トライアルアカウントは事前に作成済みです。お渡ししたログイン情報で Snowsight にログインしてください。

### 0-1. GitHub リポジトリをワークスペースに取り込む

Snowsight から GitHub の公開リポジトリを読み込むには、Git 用の API 統合が 1 つ必要です。

1. **Projects » Workspaces** で新しい SQL ファイルを開き、ロールを `ACCOUNTADMIN` にして、次を実行します

```sql
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE API INTEGRATION handson_git
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com')
  ENABLED = TRUE;
```

2. **Workspaces** メニューから **From Git repository** を選びます
3. **Repository URL** に、次の URL を貼り付けます：`https://github.com/sfc-gh-tshoji/snowflake-handson`
4. **API Integration** に `HANDSON_GIT` を選び、認証方法は **Public repository** を選んで **Create** を押します（公開リポジトリのため認証は不要です。変更の push はできません）

作成したワークスペースに `README.md`（本手順書）、`redshift_assets/`、`sql/` が表示されれば完了です。

### 0-2. セットアップを実行する

1. ワークスペースで `sql/01_setup.sql` を開き、**全文を実行**します（約 1 分。ロールは `ACCOUNTADMIN` のままで構いません）。なお、セットアップではモデルが東京リージョンに無い場合に備えて Cortex のクロスリージョン推論を有効にします（本番では別途ご判断ください）
2. 最後の確認クエリで `STORE_MASTER 20 / PRODUCT_MASTER 60 / SALES_DETAIL 3000000` が出れば完了です
3. Snowsight の **Cortex Code（CoCo）** を開き（Workspaces のエディタ付近のアイコンから開けます）、動作確認として次を入力します

```
RETAIL_HANDSON データベースにどんなスキーマとテーブルがあるか、件数つきで教えて
```

`RS_EXPORT` に 3 テーブルが表示されれば OK です。

4. 以降は、ロールを `HANDSON_ROLE`、ウェアハウスを `HANDSON_WH` に切り替えて進めます（Snowsight 右上のロール切替、またはエディタで `USE ROLE HANDSON_ROLE; USE WAREHOUSE HANDSON_WH;` を実行）

**想定シナリオ**: 化粧品を扱う小売企業が、Redshift 上の基盤（架空の構成）を Snowflake へ移し、売上の定義を 1 つにそろえ、現場が自然言語で分析できるようにします。

---

## 第 1 幕：Redshift の SQL・DDL を Snowflake に変換して検証する（20分）

Redshift には接続しません。ワークスペースの `redshift_assets/` にある **Redshift 方言の SQL** を CoCo に渡し、Snowflake 向けに変換して、結果を突合します。
変換元のデータは、Redshift から UNLOAD した想定で `RETAIL_HANDSON.RS_EXPORT` に入っています。

### 1-1. DDL の変換（8分）

`redshift_assets/rs_01_ddl.sql` を開き、ファイルを開いた状態で CoCo に依頼します（うまく渡せない場合は、ファイルの全文を貼り付けます）。

```
開いている Redshift の DDL を Snowflake 向けに変換して。作成先は RETAIL_HANDSON.DWH スキーマ。
Snowflake で不要になる指定は何かも説明して。変換後の DDL は実行前に見せて
```

確認ポイント：
- `ENCODE` / `DISTSTYLE` / `DISTKEY` / `SORTKEY` がどう扱われたか（Snowflake では物理配置の指定が不要）
- 型（`SMALLINT` `DECIMAL(12,0)`）や `DEFAULT GETDATE()` の置き換え

内容を確認して実行し、続けてデータを投入します。

```
RS_EXPORT の STORE_MASTER / PRODUCT_MASTER / SALES_DETAIL から、DWH の DIM_STORE / DIM_PRODUCT / FACT_SALES にデータを投入して。
列名の対応を確認してから実行して
```

### 1-2. マート作成クエリの変換と突合（12分）

`redshift_assets/rs_02_mart.sql` を開いた状態で CoCo に依頼します。

```
開いている Redshift のマート作成クエリを Snowflake 向けに変換して、DWH スキーマに MART_MONTHLY_BRAND_SALES として作成して。
Redshift 固有の関数や構文で、置き換えたものと、そのまま使えたものを分けて説明して
```

確認ポイント：
- `APPROXIMATE COUNT(DISTINCT ...)`、`GETDATE()` など、変換が必要だった箇所
- `DECODE` / `NVL` / `LISTAGG` のように、そのまま使えた箇所

作成できたら、**Redshift 側で取得済みの想定値**と突合します。

| 項目 | 想定値 |
|---|---|
| DIM_STORE の件数 | 20 |
| DIM_PRODUCT の件数 | 60 |
| FACT_SALES の件数 | 3,000,000 |
| FACT_SALES の `SALES_AMOUNT_TAX_IN` 合計 | 18,527,975,000 |
| FACT_SALES の返品件数（`RETURN_FLAG = 1`） | 151,888 |
| MART_MONTHLY_BRAND_SALES の行数 | 90 |
| MART の `GROSS_TAX_IN` 合計 | 18,527,975,000 |
| MART の `NET_TAX_IN` 合計 | 17,599,558,075 |

```
上の想定値と、DWH の実際の値を突合する SQL を書いて実行して。一致/不一致を一覧で見せて
```

### 1-3. 【発展・予備時間に実施】ストアドプロシージャの変換（5分）

`redshift_assets/rs_03_procedure.sql`（plpgsql）を開いた状態で、Snowflake Scripting への変換を依頼します。

```
開いている Redshift ストアドプロシージャを Snowflake Scripting に変換して。DWH スキーマに SP_REFRESH_MART として作成し、2026-01-01 を引数に呼び出して結果を確認して
```

---

## 第 2 幕：部門ごとに違う「売上」の定義を 1 つにまとめる（20分）

「売上」の意味が部門ごとに違うと、会議で数字が合いません。ここでは次の 2 つの定義を題材にします（`redshift_assets/rs_04_dept_definitions.sql`）。

- 営業部門：税込金額をそのまま合計（返品を含む）
- 経理部門：返品を除き、税抜（税率 10%）に換算して合計

### 2-1. ずれを確認する（5分）

```
開いている 2 つの SQL を実行して、月別の「売上」を並べて比較して。差が出る理由を、返品と税の 2 つの要因に分けて金額で説明して
```

### 2-2. Semantic View に定義を一本化する（15分）

```
DWH の FACT_SALES / DIM_STORE / DIM_PRODUCT をもとに、Semantic View SV_RETAIL_SALES を作って。
- 「売上」の正式な定義は経理部門のもの（返品を除く、税抜）。指標名は net_sales
- 総売上（税込・返品含む）は gross_sales_tax_in とし、明示された場合のみ使うとコメントに書く
- 返品率 return_rate と販売数量 qty_total も追加
- ディメンションは 販売月・チャネル・地域・ブランド・カテゴリ
- 各項目に日本語のコメントを付ける
作成前に定義を見せて
```

確認ポイント：
- 指標のコメントに「どの場面でどの定義を使うか」が書かれているか（のちに Agent が読みます）
- 作成後に、次のクエリで経理部門の月別の数字と一致するか

```sql
SELECT * FROM SEMANTIC_VIEW(SV_RETAIL_SALES DIMENSIONS sale_month METRICS net_sales, gross_sales_tax_in) ORDER BY sale_month;
```

---

## 第 3 幕：ダッシュボードを作って公開する（20分）

ダッシュボードは **Workspaces で作成し、artifact として公開**します。公開したものは、共有された人が Snowsight や CoWork から開けます。
ここでは CoCo に、**タブ分け・ドリルダウン・連動フィルター（カスケード）**を備えたダッシュボードを作ってもらいます。

### 3-1. CoCo にダッシュボードを作ってもらう（12分）

Workspaces で **Create » Dashboard** を選ぶか、CoCo に次を依頼します。

```
RETAIL_HANDSON.DWH の FACT_SALES / DIM_STORE / DIM_PRODUCT を使って、売上分析ダッシュボード「売上分析」を作って。
各タイルのクエリは、必ず次の定義にそろえて。
- 純売上 = 返品（RETURN_FLAG=1）を除いた SALES_AMOUNT_TAX_IN の合計 ÷ 1.10（SV_RETAIL_SALES の net_sales と同じ）
- 返品率 = 返品明細数 ÷ 全明細数

【タブ】3 つに分ける。既定は「サマリー」。
1. サマリー：KPI（純売上・販売数量・返品率）、月別の純売上推移（折れ線）、チャネル別の純売上構成（ドーナツ）
2. ブランド・商品：ブランド別の純売上（棒）、ブランド → カテゴリ → 商品の階層で掘り下げられる表またはグラフ（ドリルダウン）
3. 返品分析：地域 × カテゴリの返品率（ヒートマップ）、チャネル別の返品率の月別推移、返品率の高い店舗の上位 10 件（表）

【フィルター】全タブ共通。
- 期間（販売日。相対指定を含む）
- 地域 → チャネル → 店舗 の連動フィルター（上位を選ぶと下位の候補が絞り込まれる）
- ブランド → カテゴリ の連動フィルター

【操作】
- 「ブランド別の純売上」の棒をクリックすると、同じタブ内の他のタイルがそのブランドで絞り込まれる
- 「月別の純売上推移」で期間をドラッグすると、他のタイルがその期間で絞り込まれる

各タイルにクエリがあること、フィルターが全タイルに効くことを確認して、結果を説明して。
```

確認ポイント：
- タブが 3 つ作られ、フィルターを変えてもタブを移動しても選択が保たれるか
- 地域を選ぶと、チャネルと店舗の候補が絞られるか（連動フィルター）
- グラフのクリックやドラッグで、ほかのタイルが連動するか
- 純売上の合計が、第 2 幕の Semantic View と一致するか

うまく作れない部分は、会話で直します（例：「ブランド・商品タブの階層ドリルダウンが動かない。原因を調べて直して」）。

### 3-2. artifact として公開する（8分）

1. ダッシュボードのプレビューで、各タブとフィルターの動きを確認します
2. **Publish artifact** を選び、**Who has access** に `HANDSON_ROLE` を **Can view** で追加して **Create**
3. 発行されたリンクを控えます（第 4 幕で CoWork から開きます）

---

## 第 4 幕：Agent を作り、CoWork で自然言語で質問する（20分）

### 4-1. Agent Studio で Agent を作る（8分）

1. Snowsight の **AI & ML » Agents** を開き、新しい Agent を作成します（名前：`RETAIL_SALES_AGENT`、作成先：`RETAIL_HANDSON.DWH`）
2. ツールに、Semantic View を参照して分析するツールを追加し、データに `SV_RETAIL_SALES` を指定します
3. オーケストレーションの指示に、次を貼り付けます

```
「売上」は必ず net_sales（返品を除く税抜）を使う。税込・返品含むと明示された場合のみ gross_sales_tax_in を使う。
```

4. 応答の指示に「日本語で簡潔に回答し、金額は円単位・3桁区切りで示す」と入れ、サンプル質問を追加して保存します

### 4-2. CoWork で質問する（12分）

1. CoWork を開き、作成した `RETAIL_SALES_AGENT` を選びます
2. 次の順に質問します

```
月別の売上推移を見せて
ブランド別・チャネル別の売上を比べて
返品率が高い地域とカテゴリは？
税込で、返品も含めた総売上は？
```

確認ポイント：
- 「売上」の質問で `net_sales` が使われ、第 2 幕の数字と一致するか（回答のトレースで確認）
- 4 問目で `gross_sales_tax_in` に切り替わるか
- 回答の根拠（SQL・使った指標）を辿れるか

3. 第 3 幕で公開したダッシュボードのリンクを開き、Agent で調べた結果と見比べます（CoWork で開けない場合は Snowsight で開きます）

---

## 終了後

- `sql/99_cleanup.sql` を実行し、ウェアハウスを停止します（環境を残さない場合は、コメントの DROP も実行）
- トライアル環境は有効期限が過ぎると利用できなくなります。実データ・機密情報は投入しないでください

## 注意点

- CoCo が生成した SQL・定義は、必ず人がレビューしてから実行します
- CoCo の権限は、操作しているロールに従います（ロールが持たない権限では実行できません）
- 本ハンズオンは **SQL・DDL の変換と検証の体験**です。Redshift 実環境への接続、S3 からのロード、ETL ジョブ（SAP Data Services / JP1 など）の移行は含みません
