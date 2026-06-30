---
title: Identity
nav_order: 7
parent: SDK
---

# Identity

`BSV::Identity::Client` resolves, reveals, and revokes BSV identity certificates on the
overlay network. It wraps the wallet's certificate-discovery methods and the overlay
broadcaster/resolver into a single class with three operations.

Identity certificates are issued by certifiers using `Auth::MasterCertificate` (BRC-52/53)
and then published on-chain by the subject. `Identity::Client` handles the on-chain side;
see [Auth](auth.md) for certificate creation and selective disclosure.

## Client setup

```ruby
require 'bsv-sdk'

# wallet must implement the full BRC-100 interface (bsv-wallet Client)
client = BSV::Identity::Client.new(wallet: my_wallet)
```

Optional parameters:

```ruby
client = BSV::Identity::Client.new(
  wallet:               my_wallet,
  originator:           'myapp.example.com',  # FQDN of originating application
  certificate_verifier: ->(cert) { my_verify(cert) },
  broadcaster:          my_broadcaster,  # injectable for testing
  resolver:             my_resolver       # injectable for testing
)
```

## resolve_by_identity_key

Looks up publicly revealed identities associated with a BSV public key.

```ruby
results = client.resolve_by_identity_key(identity_key: '02abc...')

results.each do |identity|
  puts identity.name            # => 'Alice'
  puts identity.abbreviated_key # => '02abc123de...'
  puts identity.badge_label     # => 'Email certified by SocialCert'
end
```

Returns an array of `BSV::Identity::DisplayableIdentity` objects, ready for display in a
user interface. Each entry carries `name`, `avatar_url`, `abbreviated_key`, `identity_key`,
`badge_icon_url`, `badge_label`, and `badge_click_url`.

An empty array is returned when no revealed certificates are found for the given key.

## resolve_by_attributes

Searches for identities matching specific certificate field values.

```ruby
results = client.resolve_by_attributes(
  attributes: { 'email' => 'alice@example.com' }
)

results.each { |id| puts id.name }
```

Accepts `limit:` and `offset:` for pagination (both methods).

## publicly_reveal_attributes

Publishes selected certificate fields on-chain so that other parties can discover them.

The subject proves the selected fields to the `'anyone'` verifier (the generator point public
key) and broadcasts a PushDrop token to the `tm_identity` overlay topic.

```ruby
# certificate is a Hash as returned by wallet.discover_by_identity_key
result = client.publicly_reveal_attributes(
  certificate,
  fields_to_reveal: ['email']  # selective — only the email field is published
)
```

Only the fields listed in `fields_to_reveal` are written on-chain. Encrypted values for
unrevealed fields are never broadcast. The method raises `ArgumentError` if
`fields_to_reveal` is empty.

## revoke_certificate_revelation

Spends the on-chain identity token, removing the public revelation.

```ruby
client.revoke_certificate_revelation(certificate['serial_number'])
```

Internally: queries `ls_identity` for the revelation output, builds a spending transaction via
`wallet.create_action`, signs it with `PushDropTemplate`, and broadcasts to `tm_identity`.

## Worked example

```ruby
# 1. Resolve Alice's public identity
client  = BSV::Identity::Client.new(wallet: my_wallet)
results = client.resolve_by_identity_key(identity_key: alice_pubkey)

if results.empty?
  puts 'No public identity found'
else
  id = results.first
  puts "Name: #{id.name}"
  puts "Badge: #{id.badge_label}"
end

# 2. Publish your own email certificate (you hold the MasterCertificate)
client.publicly_reveal_attributes(my_email_cert, fields_to_reveal: ['email'])

# 3. Revoke it later
client.revoke_certificate_revelation(my_email_cert['serial_number'])
```

## Auth-certificate relationship

`Identity::Client` does not create certificates — that is `Auth::MasterCertificate`'s
responsibility. The typical flow is:

1. A certifier issues a `MasterCertificate` to your subject key (BRC-53).
2. You call `Identity::Client#publicly_reveal_attributes` to publish selected fields on-chain.
3. Others call `Identity::Client#resolve_by_identity_key` to discover your public identity.

For certificate verification during resolution, pass a `certificate_verifier:` callable to
`Identity::Client.new`. The default verifier raises `NotImplementedError` as a reminder that
verification must be explicitly wired up — it is never silently skipped.

## Cross-SDK gap: ContactsManager

The TypeScript and Python SDKs include a `ContactsManager` for managing a local contacts
list linked to identity certificates. This class is not present in the Ruby SDK. If you
need contacts management, track the gap in [GitHub issue #880](https://github.com/sgbett/bsv-ruby-sdk/issues/880).

## Overlay topics

| Constant | Value | Purpose |
|----------|-------|---------|
| `BSV::Identity::Constants::TOPIC` | `'tm_identity'` | Broadcast identity tokens |
| `BSV::Identity::Constants::SERVICE` | `'ls_identity'` | Query revelation outputs |
