/// @file        gv2_trusted_keys.dart
/// @description Group protocol v2 — the server keys this build trusts, per
///              server environment: the zkgroup server public params and the
///              Ed25519 key that signs the head of every accepted change log
///              entry. They are part of the build, as Signal ships its
///              zkgroup params, so a server cannot hand one account other
///              keys than everyone else gets (with other zk params it could
///              tell that account's presentations apart; with another log
///              key it could show that account another log and leave no
///              evidence). What the server publishes at GET /zk/params is
///              only compared with these (gv2_credentials.dart).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (the release gate is tool/require_server_keys.dart). Earlier 2026-11-22 (prod keys pinned — generated on the production host for the beta
///              reset, build 1000). Earlier 2026-11-20 (gv2GroupsAvailable: whether groups can run in this build at all — the
///              group entry points are hidden without it)
///
/// @functions
///  - Gv2TrustedServerKeys: the two public keys
///  - gv2TrustedServerKeysFor(env): the keys of a SERVER_ENV, or null when
///    this build trusts none there (group protocol v2 then does not run)
///  - gv2TrustedServerKeys: the keys of the environment this build talks to
///  - gv2GroupsAvailable: whether this build trusts server keys at all (else
///    groups never run here and their entry points are hidden)
///
/// Notes:
///  - dev: the development server derives both keys from fixed public labels
///    (server/src/services/ZkServerKeys.ts), so they are the same on every
///    machine and survive a restart. They are public by construction and the
///    server refuses them in production. A server test pins their hash; when
///    a libsignal upgrade changes the derivation, both change together.
///  - prod: generated once on the production host for the beta reset
///    (2026-11-22; ZK_SERVER_SECRET_PARAMS, GV2_LOG_SIGNING_KEY in its
///    environment, never off the host); the public halves below are what
///    GET /api/v2/zk/params returns there.
///  - Changing these keys is an app release: credentials and endorsements
///    issued under the old ones are erased when the new build first runs
///    (Gv2Store.saveServerKeys), and every group's title still commits to the
///    keys it was created under until an admin renames it.
library;

import 'dart:convert';
import 'dart:typed_data';

class Gv2TrustedServerKeys {
  /// ServerPublicParams.serialize() of the server's zkgroup params.
  final Uint8List serverPublicParams;

  /// The 32-byte Ed25519 public key that verifies the server's head
  /// signatures.
  final Uint8List headPublicKey;

  const Gv2TrustedServerKeys({
    required this.serverPublicParams,
    required this.headPublicKey,
  });
}

const String _devServerPublicParams =
    'AHqOHvPo1PQ4CfRFrLHSRXstXHmktMjdzBb+Fx46rm9s2AZapNLIFxakmIll3rCS2TslMASk'
    'lMfCpdt0YKf+/Coe+80O4hXL/WU1DFn6zN4WfHWuJV7EAjpqowFm4PrlS7C/cr5L95iE4JH8'
    'uqo+4ehhVjAeA5Or896X4S8YIpQvxowiM/bFse7njV4PDDVxj+cC6Y5BQOfH1Gl0VqIFsx5o'
    '6J1bcEzD8MRj8Ity1PefwL5C4I1L2dYw/uQ92ry3Q4QzwLq8UfOdq++5F3qgfGgnq8XXs2ar'
    'wiXHk+2/4nQCDICf6JNapV0ctpYWczHQvfMBWJr6CEFJSB2iLXAR4TdajLUc+Tq7/Ff5Xw2r'
    'd1MSUD4GOSVifK0Ifjm4RAP+V65WrFSnZegU1ryDNtKLerbVSAy/+C3bge2PuMfjUm4hYgKW'
    'KtqrRIczcGsg7+j2YrniC2ssrJOFN9+7ygiFB2u2iGYOcdOS4u1MGsXz3+YL3yslMWCkwJtZ'
    'VPkYDtt4YuyPeuIMnK0PrK/fyNSBMfdNcDrzix3LjtiMobpthCg12goDV/qf+As8CpP0C9lw'
    'WFKNhsMtqMSRDvOU0H1kdHlw0riIGebCmNByqT4fUhsAVNTGGQ4SruFpJvebxsXCfwS17lcs'
    'qV5zht04eAk1iz+TCIU2Mk2D6BcPePUwYJ50jrt3oyXr3GKevDn+vrCIsL3fY3GMaoVMJXTe'
    'sSxTMgS+x8K8BvFsyu9bwoCrtTh5WvKCUEyFLBBGHgLwtBz3MaQ5VtHep6sdV79I0+8WNVqD'
    'ZmuSBCQzKmrtHyfVPulHDuBUQaCZRqdalcIRQed0eCNfjblmt/sIXzPL44i70DlGvWLFj2dA'
    'ydK2WtpLQduTKDllny843AGqcfxWK301dg==';

const String _devHeadPublicKey = 'LNQcGtQNQPc+fxcA9ElutVLm41UWkZZP5+RqAg3n/0E=';

/// Production (snowchat.calidalab.ai), generated 2026-11-22 for the beta reset
/// (build 1000). Taken from GET /api/v2/zk/params of the production server.
const String _prodServerPublicParams =
    'ACLvc3t18gllOxRhkm97qeTQCmhgK9RCjZLn8lsOdf8wWpfzluiXqx5dVek3XguxiL6a1JP4'
    'YuK2qET3R103Aj4a9l7oVGEZhqu5I87P9q6vJU4wp7ckIuEjF1ysBwT+GTyCQ8YiOh4BxYyF'
    'bPsQAUfASVLm4MEgWqbOtlIrmRAAmt5fsCxyf0ksmR8vw2Ef+KFINO4L7u0bBCaniJlqAHR2'
    'RtsHDdFeMxpKpD2jNQ71rdnWmMs51cBn0nN3hYODcALpBSc/s6qJQavAN8WNyrQ53DrVFbIT'
    'Q30KpDPiBGBegpC0nQlhRk76tbQZpG4KVX/43C3d2Pg41E8j7YLW0ztWkZO7+KUeKDEKToB+'
    '0/oth9rKzTHT8PJfAsiCpY+UcXKd82fEFzeYWc4ozQiqbyUF1mHHtYVxx5aPJTKCDkVdCsKb'
    'ZItUSuExlNf9qzxyeKKw/+3oCbD8v85cfqnKdH60elTDRiA9NFJ4oqoPA8Pc9B05MjNkGVSl'
    'jOtcwLeKGSzhGyd1Wb4olzii113SXur7fDMGJzvjQeE2Pthj2yVj1ADcmB0BRjrZWL+04tWa'
    '5CzExnjxd3ytXxZOgMH4I1LQtUgT/8gOzWoeKWEHE3jeirjKwu2KotW3ONRo+W66Yy6/xltN'
    'XzdSULVJCVd7rGc2wJxsMn7W++dY9clXMx8aUKGLe3pe6zdF/r+nCkQUeLynLe22pNOb7yrG'
    'PU8BvDZUzeKIJsb18TZKlXb4UWjhKPQ3qBGcHQsWLDgejJFNYRgw0CiSjQqrFRYACdccqgHF'
    'Vq8PMdESUX3y6LHqz5I2MKpo8gY4QaoAHJTMbM2PGuG0ZDBBE/IwQFgm5HFv4iL4j5ifR+mw'
    'KOieK+1T8YbircU5BVlCnxVUOloosQCxVg==';

const String _prodHeadPublicKey = 'EewcsB1bfH0bEhupRI0m1gspJdOSi7aAP+Tk4p/7e0I=';

/// The keys this build trusts on the server of [env] (`dev` or `prod`, as in
/// SERVER_ENV), or null when it trusts none there.
Gv2TrustedServerKeys? gv2TrustedServerKeysFor(String env) {
  switch (env) {
    case 'dev':
      return Gv2TrustedServerKeys(
        serverPublicParams: base64Decode(_devServerPublicParams),
        headPublicKey: base64Decode(_devHeadPublicKey),
      );
    case 'prod':
      return Gv2TrustedServerKeys(
        serverPublicParams: base64Decode(_prodServerPublicParams),
        headPublicKey: base64Decode(_prodHeadPublicKey),
      );
    default:
      return null;
  }
}

/// The keys of the server this build talks to (SERVER_ENV), or null.
final Gv2TrustedServerKeys? gv2TrustedServerKeys = gv2TrustedServerKeysFor(
  const String.fromEnvironment('SERVER_ENV', defaultValue: 'dev'),
);

/// Whether groups can run in this build at all: it pins the server keys of
/// the environment it talks to. Without them the group entry points (create
/// a group, the group message retention setting) are hidden — never shown as
/// "not ready" forever. A release build cannot lack them
/// (tool/require_server_keys.dart).
bool get gv2GroupsAvailable => gv2TrustedServerKeys != null;
