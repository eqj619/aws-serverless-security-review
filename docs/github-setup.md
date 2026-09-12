# GitHub での公開・管理手順

このリポジトリは初回コミット済みの状態で納品されています。以下の手順でご自身の GitHub
アカウントに push してください。

> 作成環境（Claude のクラウドコンテナ）には GitHub の認証情報がないため、push はお手元の
> 環境で実行していただく形になります。

## 1. GitHub 上に空のリポジトリを作成

GitHub で新規リポジトリを作成します（README / .gitignore / LICENSE は**追加しない**でくだ
さい。すでにこのリポジトリに含まれているため、追加すると初回 push で競合します）。

推奨リポジトリ名: `aws-serverless-security-review`
公開設定: セキュリティレビュー用の社内運用であれば Private を推奨します。

`gh` CLI がある場合は、ローカルで次の 1 コマンドでも作成できます。

```bash
gh repo create aws-serverless-security-review --private --source=. --remote=origin --push
```

## 2. リモートを登録して push

`gh` を使わない場合:

```bash
cd aws-serverless-security-review
git remote add origin git@github.com:eqj619/aws-serverless-security-review.git
git push -u origin main
```

HTTPS を使う場合は `https://github.com/eqj619/aws-serverless-security-review.git`
を指定してください。認証には SSH 鍵、または Personal Access Token の利用を推奨します。

## 3. Claude Code への導入

```bash
# 個人用（全プロジェクトで有効）
git clone git@github.com:eqj619/aws-serverless-security-review.git \
  ~/.claude/skills/aws-serverless-security-review

# プロジェクト単位（チームで共有する場合）
git clone git@github.com:eqj619/aws-serverless-security-review.git \
  .claude/skills/aws-serverless-security-review
```

プロジェクト単位で共有する場合は、対象プロジェクト側で submodule にする方法もあります。

```bash
git submodule add git@github.com:eqj619/aws-serverless-security-review.git \
  .claude/skills/aws-serverless-security-review
```

## 4. 運用のヒント

- **スキルの改善は PR で。** 検出漏れや誤検知が見つかったら `references/layer-checklist.md`
  にチェック項目を追記し、変更理由を PR に書いて履歴に残すと、チームで判断基準を共有でき
  ます。
- **`security_issues.md` はこのリポジトリではなく、レビュー対象のリポジトリに置きます。**
  このリポジトリが持つのはテンプレート（`assets/security_issues_template.md`）だけです。
- **evidence/ はコミットしない。** `.gitignore` で除外済みですが、AWS の設定ダンプにはアカ
  ウント ID やリソース名が含まれます。共有前に必ず確認してください。
- **タグでバージョンを打つ。** レビュー結果に「どのバージョンのスキルで実施したか」を残せる
  ので、基準の変化を追えます。

```bash
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0
```
