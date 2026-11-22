/// @file        contact_notice.dart
/// @description The two sealed contact notices (design 2026-11-22-friend-graph-off-server §5.2,
///              contract §12.4): the inner JSON a peer finds in an ordinary sealed 1:1 envelope.
///              contact_added — "I added you" (a request, or the acceptance of yours) — travels
///              as a normal sealed row and is pushed like a message; contact_removed — "I removed
///              you" (an unfriend or a cancelled request) — as a silent sealed_control row.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (ContactNotice.answer — a contact_added marked `"answer":true`, sent
///              once in reply to a contact_added from an account in this user's list and never
///              answered itself; contactNoticeIsAnswer())
///
/// @functions
///  - contactAddedType / contactRemovedType / contactNoticeVersion: the inner type names, version
///  - contactNoticeAnswerField: the inner field that marks a contact_added as an answer
///  - contactNoticeIsAnswer(): whether an inner payload is such an answer
///  - ContactNotice: which notice, its inner JSON and the row kind it travels as
library;

/// Inner `type` of "I added you".
const String contactAddedType = 'contact_added';

/// Inner `type` of "I removed you".
const String contactRemovedType = 'contact_removed';

/// The `v` both notices carry.
const int contactNoticeVersion = 1;

/// The inner field that marks a contact_added as the answer to one.
const String contactNoticeAnswerField = 'answer';

/// Whether the inner payload [payload] of a contact_added is an answer
/// (`"answer":true`; anything else is not).
bool contactNoticeIsAnswer(Map<String, dynamic> payload) =>
    payload[contactNoticeAnswerField] == true;

/// A contact notice this device sends.
enum ContactNotice {
  /// `{"type":"contact_added","v":1,"nameCert":…}` — an ordinary sealed row
  /// (pushed). The name certificate is attached when the notice is sent.
  added,

  /// `{"type":"contact_added","v":1,"answer":true,"nameCert":…}` — the
  /// answer to a contact_added from an account in this user's list; travels
  /// like [added]. The receiver never answers it.
  answer,

  /// `{"type":"contact_removed","v":1}` — a sealed_control row (no push).
  removed;

  /// The inner JSON, without the name certificate.
  Map<String, Object?> get inner => {
        'type': this == removed ? contactRemovedType : contactAddedType,
        'v': contactNoticeVersion,
        if (this == answer) contactNoticeAnswerField: true,
      };

  /// Whether the server stores it as a silent control row.
  bool get isControl => this == removed;

  /// Whether this account's name certificate goes with it.
  bool get carriesNameCert => this != removed;

  /// Whether it is a contact_added (a request, an acceptance or an answer).
  bool get isAdded => this != removed;
}
