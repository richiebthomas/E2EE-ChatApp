class SignedPrekey {
  final int keyId;
  final String pubkey;
  final String signature;

  const SignedPrekey({
    required this.keyId,
    required this.pubkey,
    required this.signature,
  });

  factory SignedPrekey.fromJson(Map<String, dynamic> json) {
    return SignedPrekey(
      keyId: json['keyId'] as int,
      pubkey: json['pubkey'] as String,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keyId': keyId,
      'pubkey': pubkey,
      'signature': signature,
    };
  }
}

class OneTimePrekey {
  final int keyId;
  final String pubkey;

  const OneTimePrekey({
    required this.keyId,
    required this.pubkey,
  });

  factory OneTimePrekey.fromJson(Map<String, dynamic> json) {
    return OneTimePrekey(
      keyId: json['keyId'] as int,
      pubkey: json['pubkey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keyId': keyId,
      'pubkey': pubkey,
    };
  }
}

class PrekeyBundle {
  final String userId;
  final String username;
  final String identityPubkey;
  final SignedPrekey signedPrekey;
  final OneTimePrekey? oneTimePrekey; // May be null if none available

  const PrekeyBundle({
    required this.userId,
    required this.username,
    required this.identityPubkey,
    required this.signedPrekey,
    this.oneTimePrekey,
  });

  factory PrekeyBundle.fromJson(Map<String, dynamic> json) {
    return PrekeyBundle(
      userId: json['userId'] as String,
      username: json['username'] as String,
      identityPubkey: json['identityPubkey'] as String,
      signedPrekey: SignedPrekey.fromJson(json['signedPrekey'] as Map<String, dynamic>),
      oneTimePrekey: json['oneTimePrekey'] != null
          ? OneTimePrekey.fromJson(json['oneTimePrekey'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'identityPubkey': identityPubkey,
      'signedPrekey': signedPrekey.toJson(),
      'oneTimePrekey': oneTimePrekey?.toJson(),
    };
  }

  @override
  String toString() {
    return 'PrekeyBundle(userId: $userId, username: $username, hasOTP: ${oneTimePrekey != null})';
  }
}
