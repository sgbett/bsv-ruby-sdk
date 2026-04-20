## Interface Structure

The interface comprises numerous methods that cater to different functional areas related to wallet operations and application needs. The methods are grouped for easier understanding:

### Transaction Operations:

- **Creation**: The `createAction` method creates a new Action, which is effectively a Bitcoin transaction augmented with descriptive metadata and optional categorization (labels). This method can either fully construct and sign a transaction or return a "signableTransaction" reference if some inputs must be signed or processed later. The method always requires at least one input or one output to produce a valid transaction; otherwise, it must return an error. The minimum requirements is that at least one input or one output must be specified. If only `description` is provided and no inputs and no outputs are given, the wallet must return an error, since a transaction cannot be constructed. If `inputs` are provided, the wallet requires `inputBEEF` to supply context and validation data for these inputs. If both `inputBEEF` and a fully prepared set of `inputs` are provided, `inputBEEF` should provide SPV and contextual information about these inputs. The two are complementary: `inputs` define the UTXOs being consumed, and `inputBEEF` provides the transaction inclusion proofs or data needed for validation. Both must not conflict. If a conflict is detected, the wallet should return an error. Every input requires an `inputDescription`. This string documents why a particular UTXO was chosen or what it represents. This field is required to ensure proper user-level record-keeping and transparency. If `basket` is not provided for an output, that output is considered untracked by the wallet. It will not appear in `listOutputs`, and the wallet does not maintain any metadata about it. Baskets are used for grouping UTXOs for later retrieval, filtering, and permissioned operations.
- **Signing**: `signAction` allows for signing and processing previously created transactions from the `createAction` method.
- **Aborting**: `abortAction` facilitates the cancellation of transactions that have not yet been completed.
- **Internalization**: `internalizeAction` enables wallets to accept and manage incoming transactions by parsing, tagging, and organizing outputs.
- **Listing**: `listActions` and `listOutputs` allow querying transactions and outputs based on specific criteria like labels, baskets, and tags. Labels can be attached to transactions to facilitate discovery via `listActions` and tags can be attached to outputs to similarly facilitate discovery via `listOutputs`. They are purely organizational tools and cannot be used as triggers or conditional hooks for other wallet operations. They serve only for later searching and categorizing actions.
- **Relinquishment:** `relinquishOutput` releases an output from a basket tracked by the wallet, even if it has yet to be spent.
- **Pre-Built Transactions**: If you already have a fully constructed transaction in BEEF format and simply need to internalize it into the wallet, `internalizeAction` is the appropriate method. `createAction` is meant for constructing new transactions within the wallet, not for just adding an existing transaction.
- **Tags vs. Labels**: Transaction-level labels categorize entire transactions (Actions) and are used with `listActions`. Output-level tags categorize individual outputs and are used with `listOutputs`. Both are organizational metadata fields and do not trigger special wallet logic or external processes. They exist solely for searching, filtering, and organizing data.

### Public Key Management:

- **Key Retrieval**: `getPublicKey` facilitates the retrieval of public keys, be they derived keys based on protocols or the user's main identity keys.
- **Key Linkage**: Methods `revealCounterpartyKeyLinkage` and `revealSpecificKeyLinkage` disclose key relationships, as specified in [BRC-69](../key-derivation/0069.md), with additional support for future zero-knowledge proof schemes outlined in [BRC-97](../wallet/0097.md). These are essential for identity verification and the auditing of interactions between parties.

### Cryptography Operations:

- **Encryption/Decryption**: `encrypt` and `decrypt` methods implement secure encryption and decryption of data using derived keys and consistent protocol definitions, enabling private exchanges of information between counterparties.
- **HMAC Operations**: `createHmac` and `verifyHmac` allow for the creation and verification of Hash-based Message Authentication Codes (HMAC) to ensure data integrity.
- **Signatures**: `createSignature` and `verifySignature` enable the creation and verification of digital signatures, both public and private, essential for validating the authenticity of transactions, documents, and data.

### Identity and Certificate Management:

- **Certificate Acquisition**: `acquireCertificate` allows the wallet to obtain identity certificates, either by directly saving them or through a standardized issuance protocol. Conversely, `relinquishCertificate` allows an old certificate to be removed.
- **Certificate Listing and Discovery**: `listCertificates`, `discoverByIdentityKey`, and `discoverByAttributes` enable querying of identity certificates owned by the user or others based on identity keys or specific attributes.
- **Proving Identity Certificates**: `proveCertificate` leverages selective revelation protocols defined in [BRC-52](../peer-to-peer/0052.md) while integrating future-proof proof schemes from [BRC-97](../wallet/0097.md). This provides enhanced flexibility and enables users to securely prove their identity or certified attributes to third parties when required.

### Blockchain and Network Data:

- **Blockchain Height**: `getHeight` retrieves the current height of the blockchain.
- **Merkle Root Retrieval**: `getMerkleRootForHeight` retrieves the Merkle root at a specific block height.
- **Network and Version Information**: `getNetwork` and `getVersion` retrieve information about the network (mainnet or testnet) and the wallet's version.

### Authentication:

- **User Authentication**: `isAuthenticated` checks the user's authentication status, ensuring they've set up their wallet before operations are attempted.
- **Authentication Wait**: `waitForAuthentication` waits for the user to complete authentication and returns once the wallet has been fully set up.

## Data Types and Constraints

To ensure consistency and prevent errors, the interface defines various data types and associated constraints. A few key examples include:

### Boolean Types:

- `BooleanDefaultFalse`: Defaults to false if not provided.
- `BooleanDefaultTrue`: Defaults to true if not provided.

### Integer Types:

- `Byte`: An integer between 0 and 255.
- `PositiveIntegerOrZero`: A non-negative integer with an upper bound of 2^32 - 1.
- `PositiveIntegerMax10`: A positive integer between 1 and 10.
- `PositiveIntegerDefault10Max10000`: A positive integer that defaults to 10, and has an upper bound of 10000.
- `SatoshiValue`: Represents a value in Satoshis, ranging between 1 and 2.1 \* 10^15.

### String Types:

- `ISOTimestampString`: Represents an ISO 8601 format timestamp.
- `HexString`: A string containing hexadecimal characters.
- `Base64String`: A string in standard base64 encoded format.
- **Specialized Strings**: Defined for specific fields, including transactions, descriptions, version strings, certificate field names, etc.
