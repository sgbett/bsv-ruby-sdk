# frozen_string_literal: true

RSpec.describe BSV::Transaction::Beef do
  # Go SDK test vector: BEEF V1 (BRC-62) with 1 BUMP and 2 transactions
  let(:brc62_hex) do
    '0100beef01fe636d0c0007021400fe507c0c7aa754cef1f7889d5fd395cf1f785dd7de98eed895dbedfe4e5bc70d' \
      '1502ac4e164f5bc16746bb0868404292ac8318bbac3800e4aad13a014da427adce3e010b00bc4ff395efd11719b2' \
      '77694cface5aa50d085a0bb81f613f70313acd28cf4557010400574b2d9142b8d28b61d88e3b2c3f44d858411356' \
      'b49a28a4643b6d1a6a092a5201030051a05fc84d531b5d250c23f4f886f6812f9fe3f402d61607f977b4ecd2701c' \
      '19010000fd781529d58fc2523cf396a7f25440b409857e7e221766c57214b1d38c7b481f01010062f542f45ea366' \
      '0f86c013ced80534cb5fd4c19d66c56e7e8c5d4bf2d40acc5e010100b121e91836fd7cd5102b654e9f72f3cf6fdb' \
      'fd0b161c53a9c54b12c841126331020100000001cd4e4cac3c7b56920d1e7655e7e260d31f29d9a388d04910f1bb' \
      'd72304a79029010000006b483045022100e75279a205a547c445719420aa3138bf14743e3f42618e5f86a19bde14bb' \
      '95f7022064777d34776b05d816daf1699493fcdf2ef5a5ab1ad710d9c97bfb5b8f7cef3641210263e2dee22b1ddc' \
      '5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013e660000000000001976a9146bfd5c7f' \
      'be21529d45803dbcf0c87dd3c71efbc288ac0000000001000100000001ac4e164f5bc16746bb0868404292ac8318' \
      'bbac3800e4aad13a014da427adce3e000000006a47304402203a61a2e931612b4bda08d541cfb980885173b8dcf6' \
      '4a3471238ae7abcd368d6402204cbf24f04b9aa2256d8901f0ed97866603d2be8324c2bfb7a37bf8fc90edd5b441' \
      '210263e2dee22b1ddc5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013c660000000000' \
      '001976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac0000000000'
  end

  # Go SDK test vector: BEEF V2 (BRC-96) with 3 BUMPs and 3 transactions
  let(:beef_set_hex) do
    '0200beef03fef1550d001102fd20c2009591fd79f7fb1fbd24c2fdc4911da930e1d7386f0216b6446b85eea29f97' \
      '8f1bfd21c202ac2a05abdae46fc2555c36a76035dedbf9fac4fc349eabffbd9d62ba440ffcb101fd116100cabeb7' \
      '14ea9a3f15a5e4f6138f6dd6b75bab32d8b40d178a0514e6e1e1b372f701fd8930007e04df7216a1d29bb8caabd1' \
      'f78014b1b4f336eb6aee76bcf1797456ddc86b7501fd451800796afe5b113d8933f5eef2d180e72dc4b644fd76fb' \
      '1243dfb791d9863702573701fd230c007a6edc003e02c429391cbf426816885731cb8054410599884eed508917a2' \
      'f57c01fd100600eaa540de74506ed6abcb48e38cc544c53d373269271a7e6cf2143b7cc85d7ea401fd0903001e31' \
      'aa04628b99d6cfa3e21fb4a7e773487ebc86a504e511eaff3f2176267b9401fd85010031e0d053497f85228b0287' \
      '9f69c4c7b43fb5abc3e0e47ea49a63853b117c9b5001c30083339d5a5b97ad77b74d3538678bb20ea7e61f8b02c2' \
      '4a625933eb496bebd3480160008ee445baec1613d591344a9915d77652f508e6442cd394626a3ff308bcb151f101' \
      '3100f3f68f2a72e47bb41377e9e429daa496cd220bdcf702a36a209f9feba58d5552011900a01c52f4099bc7bdfe' \
      'a772ab03739bf009d72f24f68b5c4f8cc71a8c4da80804010d00c2ce2d5bfb9cbab9983ae1c871974f23a32c585d' \
      '9b8440acc4ef5203c1d6c05401070072c7fc59a1717e90633f10d322e0f63272ae97c017d1efae04e4090abeeafa' \
      'c3010200a7aa5fa5576d1de6dd0e32d769592bc247be7bbd0b3e36e2d579fa1ec7d6ebce010000090cba670bea2e' \
      '0d5c36e979e4cf9f79ad0874d734fb782fec2496d4c554e321010100d963646680643df73c34d7fa16f173595cf3' \
      '2a9ed6f64d2c8ee88a8af6b7bf52fedf590d001202fe66130200023275c6dde10d32d61af52b412b1e3956b5cd08' \
      '5605cd521778f11d53849fdb0cfe6713020000cd5e2298cf4d809c698c8adeeab66718e6b75b3d528bce74e6e01b' \
      '984c736df901feb209010000736013454e087c89d813c99a043c9029cf2d427815c6a98ba3641c384ae52c4701fd' \
      'd884007f742824bddca1582e4ded866d9609d9473397f8b86625376be74684f7fb947f01fd6d4200eb7f54ce4f92' \
      '0a3e4c7f96ef6b2d199c519df1b1286415581187ca608f3e47b801fd372100fa6c1c8cba3d3d5d030cd98eb91498' \
      'cdffe70f0dad1000e123157d5dac22e22a01fd9a1000104c0294e478fbcac4e2325403afd86370c86043f295978b' \
      '809004b2687a6c9a01fd4c08009ef5a5eaf16cab45a239c43852296ab323ca21faf256ab9768dd0a2f39970ec201' \
      'fd2704006161cbd1755b66815eb69613b574920e9e836c8c3772aa2260ad3639848d520b01fd1202005e04b5afc0' \
      'ea8d29dc22b611536832a2a2e7c860bbf4227ce0bdcc8a0e66284601fd0801009719f5f90e3937f3921045d20252' \
      '2fe315da1331acc3cce472c4b084d0debe65018500d79a1c3d45a3c41bf6526a9adbac2676159d2f3c753d7d3b6d' \
      'ba1dc3cbdd3c520143006b88b582d985bffc511556e471a6a20cfda2d41837245329f714214e009a3e48012000c1' \
      '840dbdfc3014f1e912882b971c030fd21c0b023c01fe6fd7470d6d9bb2ab86011100f9c3de08d38588e225a5ee53' \
      '34a3c03771a0b51318ca388dd1b5826951604d750109006e2b2e926c86214620d306a59522eee438a79157e9360c' \
      'b76ee14a868fccc482010500d5c43ea372c432861db73ba0a6897fa29855e542a6ed910626dfb8954d94fa470103' \
      '00d7863bafb5ca841ca0b13736fced1d492f0f741cb0a2beab1cafa517c878ae2c010000174ccda0879c20b85fa2' \
      '6d423deb0b34c5f2787127e244ccacfae39b5ba8fea7feeb590d001602fe46b3060002fa6ae8371111956f74412e' \
      '3b1effcbd4fcb278124b6365b34c8cc20a5287bafffe47b306000011883eed76bdc7e7fb79efe23e3c50aa825ade' \
      '46d79895de1a246e3d69a5b8cf01fea2590300009c92d7f67ac06e4bce0de4f18f438056f25138ee1a0cf61ed3a6' \
      'd7f32261339b01fed0ac01000006178026214d61dc19c91cb5c08481f2f3daf03392c359de424cbd5d7135c5cf01' \
      'fd69d6000174f6863438909d648fea32cdd65cbf457ab717f9be327d5d4352dbf157671e01fd356b0059536ea550' \
      '10906b7071e36f78b20faaaede46a7f27ba4916dc1655836c73de701fd9b3500dee845c02c827dbcd862de359f5e' \
      '6ad0ecca59213d9eb01896374d9efb7af9fd01fdcc1a00b22861b84b4537dfdaa8eb51957a51007af7836677ad14' \
      '074601de6cd6c2871c01fd670d00591e76e7b07b26a6d7e940ec4f84497d9f3c7be111b15c336b24d83227db0c10' \
      '01fdb20600f142d0ff9b2ddb7c21d8913f02adc7abc51fcdd5253154339450b87b59859aa601fd580300ce0307ff' \
      '2027d405b8afa8a5c8834e9cc8bd073c4f463c3657562bbdb7843fe601fdad010027a3ce3a9829a3df0d9074099a' \
      '6a3d76c81600a6a9c50f6cf857fb823c1a783901d700cca7689680c528f0a93fd9c980577016b37ce67ce75b1d72' \
      '8c4fa23008b1652b016a00b74bd3ab6c94f1216a803849afc254f37eea378c89167ff0686223db82767e3a013400' \
      '434d5f48f733bb69fc5f0bd8238ffaec8d002951e6a1b52484fcc05819078372011b0053fef8153f4aed8aa8bdeb' \
      'eae0a6c1aa7712b84887fb565bcd9232fdd60fb0c0010c00009d9f21a9bc9e9d8c99aac9a1df47ffe02334fcb8bc' \
      '8f3797d64c2564b3bf44010700838a284a4ee33c455b303e1eb23428b35d264b35c4f4b42bd6c68f1a7279f38801' \
      '020042820e1ab5dbb77b0a6f266167b453f672d007d0c6eddc6229ce57c941f46c670100002c0da37e0453e7d01c' \
      '810d2280a84792086b1fe1bc232e76ef6783f76c57757601010048746ad4d10a562bb53d2ed29438c9dfd0a6cacb' \
      '78429277072e789d4d8dd8c101010091a52bf4a100e96dba15cbff933df60fcb26d95d6dd9b55fd5e450d5895e45' \
      '26010100c202dcbdece72a45a1657ff7dbd979b031b1c8b839bc9a3b958683226644b736030100020000000140f6' \
      '726035b03b90c1f770f0280444eeb041c45d026a8f4baaf00530bdc473a5020000006b483045022100ccdf467aa4' \
      '6d9570c4778f4e68491cc51dff4b815803d2406b6e8772d800f5ad02200ff8f11a59d207c734e9c68154dcef4023' \
      'd75c37e661ab866b1d3e3ea77e6bda4121021cf99b6763736f48e6e063f99a43bfa82f15111ba0e0f9776280e6bd' \
      '75d23af9ffffffff0377082800000000001976a91491b21f8856b862ff291ca0ac2ec924ba2419113788ac753301' \
      '00000000001976a9144b5b285395052a61328b58c6594dd66aa6003d4988acf229f503000000001976a9148efcb6' \
      'c55f5c299d48d0c74762dd811345c9093b88ac0000000001010200000001bcfe1adc5e99edb82c6a48f44cbae19b' \
      'c0e5d31f9c8e4b3a92d6befb1cb2e510020000006a4730440220211655b505edd6fe9196aba77477dac5c9f638fe' \
      '204243c09f1188a19164ac7f022035fb8640750515ca85df8197dec87a76db5c578f05b8ae645e30d8f70d429a32' \
      '4121028bf1be8161c50f98289df3ecd3185ed2273e9d448840232cf2f077f05e789c29ffffffff03d80004000000' \
      '00001976a9144f427ee5f3099f0ac571f6b723a628e7b08fb64c88ac75330100000000001976a914f7cad8703640' \
      '6e5d3aef5d4a4d65887c76f9466788ac27db1004000000001976a9143219d1b6bd74f932dcb39a5f3b48cfde2b61' \
      'cc0088ac0000000001020100000002e646efa607ff14299bc0b0cfaa65e035feb493cc440cb8abb8eb6225f8d4c1' \
      'c4000000006b483045022100b410c4f82655f56fc8de4a622d3e4a8c662198de5ca8963989d70b85734986f50220' \
      '4fe884d99aa6ffd44bb01396b9f63bebcb7222b76e6e26c2bd60837ff555f1f8412103fda4ece7b0c9150872f8ef' \
      '5241164b36a230fd9657bc43ca083d9e78bc0bcba6ffffffff3275c6dde10d32d61af52b412b1e3956b5cd085605' \
      'cd521778f11d53849fdb0c000000006a473044022057f9d55ace1945866be0f83431867c58eda32d73ae3fdabed2' \
      'd3424ebbe493530220553e286ae67bcaf49b0ea1d3163f41b1b3c91702a054e100c1e71ca4927f6dd8412103fda4' \
      'ece7b0c9150872f8ef5241164b36a230fd9657bc43ca083d9e78bc0bcba6ffffffff04400d0300000000001976a9' \
      '140e8338fa60e5391d54e99c734640e72461922d9988aca0860100000000001976a9140602787cc457f68c435812' \
      '24fda6b9555aaab58e88ac10270000000000001976a91402cfbfc3931c7c1cf712574e80e75b1c2df14b2088acd5' \
      '120000000000001976a914bd3dbab46060873e17ca754b0db0da4552c9a09388ac00000000'
  end

  describe '.from_hex (V1)' do
    let(:beef) { described_class.from_hex(brc62_hex) }

    it 'parses the correct version' do
      expect(beef.version).to eq(described_class::BEEF_V1)
    end

    it 'parses the correct number of BUMPs' do
      expect(beef.bumps.length).to eq(1)
    end

    it 'parses the correct number of transactions' do
      expect(beef.transactions.length).to eq(2)
    end

    it 'parses transactions with expected structure' do
      beef.transactions.each do |beef_tx|
        expect(beef_tx.transaction).to be_a(BSV::Transaction::Transaction)
        expect(beef_tx.transaction.inputs).not_to be_empty
        expect(beef_tx.transaction.outputs).not_to be_empty
      end
    end

    it 'attaches merkle_path to the mined transaction' do
      mined = beef.transactions.select { |bt| bt.transaction.merkle_path }
      expect(mined.length).to eq(1)
      expect(mined.first.transaction.merkle_path).to be_a(BSV::Transaction::MerklePath)
    end
  end

  describe '.from_hex (V2)' do
    let(:beef) { described_class.from_hex(beef_set_hex) }

    it 'parses the correct version' do
      expect(beef.version).to eq(described_class::BEEF_V2)
    end

    it 'parses the correct number of BUMPs' do
      expect(beef.bumps.length).to eq(3)
    end

    it 'parses the correct number of transactions' do
      expect(beef.transactions.length).to eq(3)
    end

    it 'attaches merkle_paths from BUMPs' do
      with_paths = beef.transactions.select { |bt| bt.transaction&.merkle_path }
      expect(with_paths).not_to be_empty
    end
  end

  describe '#to_hex (V2 round-trip)' do
    it 'round-trips the BEEFSet vector' do
      beef = described_class.from_hex(beef_set_hex)
      expect(beef.to_hex).to eq(beef_set_hex)
    end
  end

  describe 'source transaction wiring' do
    let(:beef) { described_class.from_hex(beef_set_hex) }

    it 'wires source transactions on child inputs' do
      wired_inputs = beef.transactions.flat_map do |bt|
        next [] unless bt.transaction

        bt.transaction.inputs.select(&:source_transaction)
      end

      expect(wired_inputs).not_to be_empty

      wired_inputs.each do |input|
        expect(input.source_transaction.txid_hex).to eq(input.txid_hex)
      end
    end
  end

  describe 'empty BEEF' do
    it 'parses V2 empty beef' do
      beef = described_class.from_hex('0200beef0000')
      expect(beef.version).to eq(described_class::BEEF_V2)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end

    it 'parses V1 empty beef' do
      beef = described_class.from_hex('0100beef0000')
      expect(beef.version).to eq(described_class::BEEF_V1)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end
  end

  describe '#find_transaction' do
    it 'finds a transaction by txid' do
      beef = described_class.from_hex(beef_set_hex)
      first_tx = beef.transactions.first.transaction
      found = beef.find_transaction(first_tx.txid)
      expect(found).to eq(first_tx)
    end

    it 'returns nil for unknown txid' do
      beef = described_class.from_hex(beef_set_hex)
      expect(beef.find_transaction("\x00".b * 32)).to be_nil
    end
  end

  describe 'Atomic BEEF' do
    it 'round-trips via to_atomic_binary and from_binary' do
      beef = described_class.from_hex(beef_set_hex)
      last_tx = beef.transactions.last.transaction
      subject_txid = last_tx.txid

      atomic_bytes = beef.to_atomic_binary(subject_txid)

      # Verify prefix
      expect(atomic_bytes.byteslice(0, 4).unpack1('V')).to eq(described_class::ATOMIC_BEEF)
      expect(atomic_bytes.byteslice(4, 32)).to eq(subject_txid)

      # Parse back
      parsed = described_class.from_binary(atomic_bytes)
      expect(parsed.subject_txid).to eq(subject_txid)
      expect(parsed.transactions.length).to eq(beef.transactions.length)

      found = parsed.find_transaction(subject_txid)
      expect(found).not_to be_nil
      expect(found.txid).to eq(subject_txid)
    end
  end

  describe 'Transaction.from_beef / Transaction#to_beef' do
    it 'round-trips Transaction.from_beef through the V2 vector' do
      beef_data = [beef_set_hex].pack('H*')
      tx = BSV::Transaction::Transaction.from_beef(beef_data)

      expect(tx).to be_a(BSV::Transaction::Transaction)
      # Subject tx is the last one in the bundle
      beef = described_class.from_hex(beef_set_hex)
      expected_txid = beef.transactions.last.transaction.txid
      expect(tx.txid).to eq(expected_txid)
    end

    it 'round-trips via from_beef_hex' do
      tx = BSV::Transaction::Transaction.from_beef_hex(beef_set_hex)
      expect(tx).to be_a(BSV::Transaction::Transaction)
    end

    it 'wires source transactions on the returned transaction' do
      tx = BSV::Transaction::Transaction.from_beef_hex(beef_set_hex)
      wired = tx.inputs.select(&:source_transaction)
      expect(wired).not_to be_empty
    end

    it 'builds a BEEF from a transaction with ancestry' do
      # Parse the BEEF to get a transaction with wired sources
      tx = BSV::Transaction::Transaction.from_beef_hex(beef_set_hex)

      # Rebuild BEEF from that transaction
      beef_binary = tx.to_beef
      expect(beef_binary.byteslice(0, 4).unpack1('V')).to eq(BSV::Transaction::Beef::BEEF_V2)

      # Parse the rebuilt BEEF
      rebuilt = described_class.from_binary(beef_binary)
      expect(rebuilt.transactions).not_to be_empty

      # The subject tx should be present
      found = rebuilt.find_transaction(tx.txid)
      expect(found).not_to be_nil
      expect(found.txid).to eq(tx.txid)
    end

    it 'to_beef_hex returns a hex string' do
      tx = BSV::Transaction::Transaction.from_beef_hex(beef_set_hex)
      hex = tx.to_beef_hex
      expect(hex).to match(/\A[0-9a-f]+\z/)
      expect([hex].pack('H*').byteslice(0, 4).unpack1('V')).to eq(BSV::Transaction::Beef::BEEF_V2)
    end
  end

  describe '#merge_bump' do
    it 'appends a new BUMP' do
      beef = described_class.new
      mp = described_class.from_hex(brc62_hex).bumps.first
      idx = beef.merge_bump(mp)
      expect(idx).to eq(0)
      expect(beef.bumps.length).to eq(1)
    end

    it 'deduplicates BUMPs with same block height and root' do
      source = described_class.from_hex(brc62_hex)
      mp = source.bumps.first

      beef = described_class.new
      idx1 = beef.merge_bump(mp)
      idx2 = beef.merge_bump(mp)
      expect(idx1).to eq(idx2)
      expect(beef.bumps.length).to eq(1)
    end
  end

  describe '#merge_transaction' do
    it 'adds a transaction and its ancestors' do
      source = described_class.from_hex(beef_set_hex)
      subject_tx = source.transactions.last.transaction

      beef = described_class.new
      beef.merge_transaction(subject_tx)

      expect(beef.transactions).not_to be_empty
      txids = beef.transactions.map(&:txid)
      expect(txids).to include(subject_tx.txid)
    end

    it 'does not duplicate transactions' do
      source = described_class.from_hex(beef_set_hex)
      subject_tx = source.transactions.last.transaction

      beef = described_class.new
      beef.merge_transaction(subject_tx)
      count_before = beef.transactions.length
      beef.merge_transaction(subject_tx)
      expect(beef.transactions.length).to eq(count_before)
    end

    it 'merges merkle paths for mined ancestors' do
      source = described_class.from_hex(beef_set_hex)
      subject_tx = source.transactions.last.transaction

      beef = described_class.new
      beef.merge_transaction(subject_tx)
      expect(beef.bumps).not_to be_empty
    end
  end

  describe '#merge' do
    it 'merges two BEEF bundles' do
      beef1 = described_class.from_hex(brc62_hex)
      beef2 = described_class.from_hex(beef_set_hex)

      count1 = beef1.transactions.length
      count2 = beef2.transactions.length

      beef1.merge(beef2)
      expect(beef1.transactions.length).to eq(count1 + count2)
    end

    it 'deduplicates when merging identical bundles' do
      beef1 = described_class.from_hex(beef_set_hex)
      beef2 = described_class.from_hex(beef_set_hex)

      beef1.merge(beef2)
      # Should still have the same number of transactions
      expect(beef1.transactions.length).to eq(3)
    end

    it 'produces valid serialisation after merge' do
      beef1 = described_class.from_hex(brc62_hex)
      beef2 = described_class.from_hex(beef_set_hex)
      beef1.merge(beef2)

      # Should serialise without error
      hex = beef1.to_hex
      expect(hex).to match(/\A[0-9a-f]+\z/)

      # Should parse back
      parsed = described_class.from_hex(hex)
      expect(parsed.transactions.length).to eq(beef1.transactions.length)
    end
  end

  describe '#make_txid_only' do
    it 'converts a transaction to TXID-only format' do
      beef = described_class.from_hex(beef_set_hex)
      tx = beef.transactions.first.transaction
      txid = tx.txid

      beef.make_txid_only(txid)
      entry = beef.transactions.find { |bt| bt.txid == txid }
      expect(entry.format).to eq(described_class::FORMAT_TXID_ONLY)
      expect(entry.known_txid).to eq(txid)
    end

    it 'returns nil for unknown txid' do
      beef = described_class.from_hex(beef_set_hex)
      expect(beef.make_txid_only("\x00".b * 32)).to be_nil
    end
  end

  describe '#valid?' do
    it 'returns true for a valid BEEF with complete ancestry' do
      beef = described_class.from_hex(beef_set_hex)
      expect(beef.valid?).to be true
    end

    it 'returns true for V1 BEEF vector' do
      beef = described_class.from_hex(brc62_hex)
      expect(beef.valid?).to be true
    end

    it 'returns true for empty BEEF' do
      beef = described_class.new
      expect(beef.valid?).to be true
    end

    it 'returns false when an unproven transaction has missing ancestors' do
      # Create a BEEF with a raw tx (no BUMP) whose input references a txid not in the bundle
      beef = described_class.new
      tx = BSV::Transaction::Transaction.from_hex(
        '010000000193a35408b6068499e0d5abd799d3e827d9bfe70c9b75ebe209c91d25072326510000000000ffffffff' \
        '02404b4c00000000001976a91404ff367be719efa79d76e4416ffb072cd53b208888acde94a905000000001976a914' \
        '04d03f746652cfcb6cb55119ab473a045137d26588ac00000000'
      )
      beef.transactions << described_class::BeefTx.new(format: described_class::FORMAT_RAW_TX, transaction: tx)
      expect(beef.valid?).to be false
    end

    it 'returns false for TXID-only entries by default' do
      beef = described_class.new
      beef.transactions << described_class::BeefTx.new(
        format: described_class::FORMAT_TXID_ONLY,
        known_txid: "\x01".b * 32
      )
      expect(beef.valid?).to be false
    end

    it 'returns true for TXID-only when allow_txid_only is true' do
      beef = described_class.new
      beef.transactions << described_class::BeefTx.new(
        format: described_class::FORMAT_TXID_ONLY,
        known_txid: "\x01".b * 32
      )
      expect(beef.valid?(allow_txid_only: true)).to be true
    end
  end

  describe '#sort_transactions!' do
    it 'preserves dependency order for already-sorted BEEF' do
      beef = described_class.from_hex(beef_set_hex)
      original_txids = beef.transactions.map(&:txid)
      beef.sort_transactions!
      expect(beef.transactions.map(&:txid)).to eq(original_txids)
    end

    it 'sorts reversed transactions into correct order' do
      beef = described_class.from_hex(beef_set_hex)
      beef.transactions.reverse!
      beef.sort_transactions!

      # After sorting, the BEEF should still be valid
      expect(beef.valid?).to be true

      # And should serialise correctly
      hex = beef.to_hex
      parsed = described_class.from_hex(hex)
      expect(parsed.transactions.length).to eq(beef.transactions.length)
    end

    it 'handles single transaction' do
      beef = described_class.from_hex(brc62_hex)
      beef.transactions.pop # keep only first tx
      expect { beef.sort_transactions! }.not_to raise_error
    end
  end

  describe 'Transaction.from_binary_with_offset' do
    it 'returns correct bytes consumed' do
      hex = '010000000193a35408b6068499e0d5abd799d3e827d9bfe70c9b75ebe209c91d2507232651' \
            '0000000000ffffffff02404b4c00000000001976a91404ff367be719efa79d76e4416ffb07' \
            '2cd53b208888acde94a905000000001976a91404d03f746652cfcb6cb55119ab473a045137' \
            'd26588ac00000000'
      binary = [hex].pack('H*')
      trailing = "\xFF".b * 10
      data = binary + trailing

      tx, consumed = BSV::Transaction::Transaction.from_binary_with_offset(data)
      expect(consumed).to eq(binary.bytesize)
      expect(tx.inputs.length).to eq(1)
      expect(tx.outputs.length).to eq(2)
    end

    it 'parses identically to from_binary' do
      hex = '010000000193a35408b6068499e0d5abd799d3e827d9bfe70c9b75ebe209c91d2507232651' \
            '0000000000ffffffff02404b4c00000000001976a91404ff367be719efa79d76e4416ffb07' \
            '2cd53b208888acde94a905000000001976a91404d03f746652cfcb6cb55119ab473a045137' \
            'd26588ac00000000'
      binary = [hex].pack('H*')

      tx1 = BSV::Transaction::Transaction.from_binary(binary)
      tx2, _consumed = BSV::Transaction::Transaction.from_binary_with_offset(binary)

      expect(tx2.to_hex).to eq(tx1.to_hex)
      expect(tx2.txid).to eq(tx1.txid)
    end
  end
end
