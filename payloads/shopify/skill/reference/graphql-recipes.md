# GraphQL recipes (Admin API 2025-04)

Save a query to a file and pass it as `@file`, or inline it in quotes.
`paginate` supplies `$n` and `$cursor` automatically.

---

## Catalogue export (active products, with taxonomy metafields)

```graphql
query($n: Int, $cursor: String) {
  products(first: $n, after: $cursor, query: "status:active") {
    nodes {
      id
      title
      handle
      vendor
      productType
      tags
      totalInventory
      featuredMedia { preview { image { url } } }
      category:       metafield(namespace: "custom", key: "category")       { value }
      subCategory1:   metafield(namespace: "custom", key: "sub_category_1")  { value }
      subCategory2:   metafield(namespace: "custom", key: "sub_category_2")  { value }
      state:          metafield(namespace: "custom", key: "state")           { value }
      suburb:         metafield(namespace: "custom", key: "suburb_and_postcode") { value }
      priceRangeV2 { minVariantPrice { amount currencyCode } }
    }
    pageInfo { hasNextPage endCursor }
  }
}
```

```bash
shopify-admin paginate bazaa @catalogue.graphql --path products > /tmp/catalogue.json
```

---

## One product by handle

```graphql
query($handle: String!) {
  productByIdentifier(identifier: { handle: $handle }) {
    id title vendor status descriptionHtml
    variants(first: 50) {
      nodes {
        id sku price inventoryQuantity
        inventoryItem { measurement { weight { value unit } } }
      }
    }
    metafields(first: 30) { nodes { namespace key value type } }
  }
}
```

```bash
shopify-admin gql bazaa @byhandle.graphql --vars '{"handle":"some-product"}'
```

---

## Find products by SKU

```graphql
query($n: Int, $cursor: String, $q: String) {
  productVariants(first: $n, after: $cursor, query: $q) {
    nodes { id sku displayName price product { id title handle } }
    pageInfo { hasNextPage endCursor }
  }
}
```

```bash
shopify-admin paginate bazaa @bysku.graphql --path productVariants --vars '{"q":"sku:ABC-*"}'
```

---

## Inventory levels per location

```graphql
query($n: Int, $cursor: String) {
  productVariants(first: $n, after: $cursor) {
    nodes {
      sku
      product { title }
      inventoryItem {
        tracked
        measurement { weight { value unit } }
        inventoryLevels(first: 10) {
          nodes { location { name } quantities(names: ["available"]) { name quantity } }
        }
      }
    }
    pageInfo { hasNextPage endCursor }
  }
}
```

Note: **`variant.weight` does not exist in 2025-04** — use
`inventoryItem.measurement.weight`.

---

## Collections and their membership counts

```graphql
query($n: Int, $cursor: String) {
  collections(first: $n, after: $cursor) {
    nodes { id title handle productsCount { count } updatedAt }
    pageInfo { hasNextPage endCursor }
  }
}
```

---

## Shop-level metafields (e.g. vendor records)

Bazaa keeps one JSON record per vendor in the `garnet-vendors` namespace;
seller addresses sit at `shipping.shippo.shipFromAddress` inside the value.

```graphql
query($n: Int, $cursor: String) {
  shop {
    metafields(first: $n, after: $cursor, namespace: "garnet-vendors") {
      nodes { key value type }
      pageInfo { hasNextPage endCursor }
    }
  }
}
```

```bash
shopify-admin paginate bazaa @vendors.graphql --path shop.metafields
```

---

## Metaobjects

```graphql
query($n: Int, $cursor: String, $type: String!) {
  metaobjects(first: $n, after: $cursor, type: $type) {
    nodes { id handle type fields { key value } }
    pageInfo { hasNextPage endCursor }
  }
}
```

List available types first:

```bash
shopify-admin gql bazaa '{ metaobjectDefinitions(first: 50) { nodes { type name } } }'
```

---

## Counts without pulling rows (cheap sanity checks)

```bash
shopify-admin gql bazaa '{
  active:  productsCount(query: "status:active")  { count }
  draft:   productsCount(query: "status:draft")   { count }
  noImage: productsCount(query: "-has:image")     { count }
}'
```

---

## ⚠️ Search-filter gotchas — read before reporting any count

**Shopify silently ignores query predicates it doesn't support.** It does not
error; it returns the unfiltered set. This will hand you a confidently wrong
number for a client report.

Verified on Bazaa, 2025-04 — `has:image` is *not* a supported product filter:

```
productsCount(query:"status:active")                  -> 9494
productsCount(query:"status:active AND has:image")    -> 9494   # ignored
productsCount(query:"status:active AND -has:image")   -> 9494   # ignored
```

**The complement test.** Before trusting any filter, run it and its negation.
A working filter's two counts sum to the unfiltered total; an ignored filter
returns the total twice.

```bash
shopify-admin gql <store> '{
  yes: productsCount(query: "status:active AND <FILTER>") { count }
  no:  productsCount(query: "status:active AND -<FILTER>") { count }
  all: productsCount(query: "status:active") { count }
}'
# yes + no == all  → the filter works.  yes == no == all → it is being ignored.
```

Confirmed working: `status:`, `product_type:`, `vendor:`, `tag:`, `sku:`,
`inventory_total:<n>`, `created_at:>…`. Confirmed ignored: `has:image`.

Also: **`productsCount` caps at 10,000** (it returned `10000` for the unfiltered
store). Treat a flat `10000` as "≥10,000", not an exact figure — narrow the query
or paginate and count.

---

## Marketing: catalogue health for a feed / shopping campaign

Anything Shopify can filter server-side, filter server-side:

```bash
# missing product type — hurts feed categorisation (filter verified working)
shopify-admin gql bazaa '{ productsCount(query: "status:active AND product_type:\"\"") { count } }'

# active but out of stock
shopify-admin gql bazaa '{ productsCount(query: "status:active AND inventory_total:<1") { count } }'
```

For **missing images** there is no working server-side filter — paginate and
filter client-side:

```graphql
query($n: Int, $cursor: String) {
  products(first: $n, after: $cursor, query: "status:active") {
    nodes { id title vendor featuredMedia { id } }
    pageInfo { hasNextPage endCursor }
  }
}
```

```bash
shopify-admin paginate bazaa @img.graphql --path products > /tmp/all.json
node -e 'const a=require("/tmp/all.json");const m=a.filter(p=>!p.featuredMedia);
  console.log(`${m.length} of ${a.length} active products have no image`);
  console.log(m.slice(0,20).map(p=>p.title).join("\n"))'
```

State the sample size in your report. If you paginated only part of the
catalogue, say so — never extrapolate a sample to a total and present it as a
count.

---

## Writes (only on explicit instruction, only where `write_allowed` is true)

Always read the current value first, echo the intended change to the user, then
mutate. Check `userErrors` on every mutation.

```graphql
mutation($input: ProductInput!) {
  productUpdate(input: $input) {
    product { id title tags }
    userErrors { field message }
  }
}
```
