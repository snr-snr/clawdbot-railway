---
name: shopify
description: "Client Shopify stores: read products, variants, inventory, collections, metafields and metaobjects across multiple client stores. Use for catalogue data, stock levels, product taxonomy, vendor data, or reconciling ad/feed data against the store."
metadata:
  version: 1.0.0
  openclaw:
    category: "marketing"
    requires:
      bins:
        - shopify-admin
    cliHelp: "shopify-admin help"
---

# Shopify Admin API access

You have direct Admin API access to the client Shopify stores configured on this
instance. **Never ask the user for credentials** — they are already installed.
Never print, echo, or write an access token into a message, log, or document.

## How to use it

Everything goes through the `shopify-admin` CLI. Run it with the Bash/shell tool.

```bash
shopify-admin stores                 # which clients are configured, and their scopes
shopify-admin whoami <store>         # confirm connectivity: shop name, domain, product count
shopify-admin scopes <store>         # what this token is actually allowed to do
shopify-admin gql <store> '<query>'  # run a GraphQL query
shopify-admin paginate <store> @file.graphql --path products --max 2000
shopify-admin rest <store> GET <path>
```

`<store>` is a slug — run `shopify-admin stores` first if you don't know it.
The slug for Bazaa (bazaa.com.au) is `bazaa`.

## Start every Shopify task like this

1. `shopify-admin stores` — resolve the client name the user said to a slug, and
   read that store's `scopes`, `no_scope`, `write_allowed`, and `notes`. The
   notes carry store-specific facts (metafield names, ID formats, gotchas) that
   will save you several wasted round trips.
2. If anything looks off, `shopify-admin whoami <store>` to confirm the
   connection before building a big query.

## Rules

1. **Read-only by default.** Some tokens hold `write_products`. Never run a
   mutation unless the user has explicitly asked you to change something in this
   turn, and the store's `write_allowed` is true. "Look at X" is never
   permission to change X. When you do mutate, report exactly what you changed.
2. **Prefer GraphQL** with tight field selections over REST — cheaper, fewer
   round trips, and the 2025-04 REST product endpoints are legacy.
3. **Paginate with `paginate`**, not by hand. Max 250 per page. Never try to pull
   ~9,500 products with a single `first:` argument.
4. **Throttling is handled for you** — the CLI backs off and retries on
   `THROTTLED`/429. Don't add your own parallel bursts; run queries sequentially.
5. **`ACCESS_DENIED` means a missing scope, not a bug.** Don't retry it or work
   around it. Check `no_scope` in the registry, tell the user which scope is
   missing and which app needs it, and stop.
6. **Never echo the token.** Don't `cat` the credentials files, don't pass tokens
   as literals, don't include them in reports. The CLI redacts its own output;
   don't route around it.
7. **Verify a filter before you report a number from it.** Shopify *silently
   ignores* search predicates it doesn't support — it returns the unfiltered set
   instead of erroring, which yields a confidently wrong figure. Before quoting
   any filtered count, run the filter and its negation: the two should sum to the
   unfiltered total. (`has:image` is a known-ignored filter — see
   `reference/graphql-recipes.md`.) `productsCount` also caps at 10,000.

## Writing queries

`paginate` requires your query to declare `$n: Int` and `$cursor: String`, pass
them to the connection as `(first: $n, after: $cursor)`, and select
`pageInfo { hasNextPage endCursor }`. It prints a JSON array of nodes.

```graphql
query($n: Int, $cursor: String) {
  products(first: $n, after: $cursor, query: "status:active") {
    nodes { id title vendor productType handle }
    pageInfo { hasNextPage endCursor }
  }
}
```

```bash
shopify-admin paginate bazaa @/tmp/q.graphql --path products --max 500 > /tmp/products.json
```

Write large result sets to a file and analyse the file. Do not paste thousands of
products into your reply.

See `reference/graphql-recipes.md` for ready-made queries: catalogue export,
metafield reads, inventory levels, vendor/shop metafields, collection membership,
and product lookup by handle or SKU.

## Adding a new client store

You cannot mint tokens yourself. Tell the user this is what you need:

1. In the client's Shopify admin: **Settings → Apps and sales channels → Develop
   apps** → create (or open) a custom app, e.g. "SNR Growth Automations".
2. Configure Admin API scopes — for catalogue/marketing work:
   `read_products` (or `write_products` only if writes are actually wanted),
   `read_inventory`, `read_metaobjects`, `read_metaobject_definitions`.
   Add `read_orders` / `read_customers` only if the task genuinely needs them.
3. Install the app, reveal the **Admin API access token** (`shpat_…`/`shpca_…`).
   It's shown once.
4. Send it to Simon over a secure channel — **not** into a chat message here.

Simon installs it with the `add-store` procedure in the OpenClaw control-center
repo (`shopify-access/README.md`). Tokens remain valid until the app is
uninstalled from the store.
