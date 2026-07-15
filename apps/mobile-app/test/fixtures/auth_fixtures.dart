/// Static sample payloads matching the shape `AuthBloc` (see
/// `lib/features/auth/bloc/auth_bloc.dart`) expects back from the API.
/// Data only — no test logic lives here.
library;

/// Sample `GET /auth/me` response body, as read by `AuthBloc._hydrate`
/// (`me.data['user']`, `me.data['claims']`).
const Map<String, dynamic> sampleAuthMeResponse = {
  'user': {
    '_id': 'user_1',
    'username': 'gs_salmank_101_22',
    'name': 'Asha Kulkarni',
    'email': 'asha.kulkarni@example.com',
    'flatNumber': 'B-402',
    'member': {
      'ownerName': 'Asha Kulkarni',
      'flatNo': '402',
      'wing': 'B',
      'flatType': '2BHK',
      'ownershipType': 'Owned',
      'carpetAreaSqft': 950,
      'builtUpAreaSqft': 1050,
      'hasVotingRights': true,
      'contactNumber': '9876500000',
      'whatsappNumber': '9876500000',
      'parkingSlots': [
        {'slotNumber': 'P-B-04', 'type': 'Covered', 'vehicleType': 'Four-Wheeler'},
      ],
      'familyMembers': [
        {'name': 'Rohan Kulkarni', 'relation': 'Spouse', 'age': 33},
      ],
    },
    'society': {'_id': 'society_1', 'name': 'Sunrise Complex', 'address': '456 Park Avenue, Pune'},
  },
  'claims': {
    'role': 'member',
    'societyId': 'society_1',
  },
};

/// Sample `POST /auth/login` response body when a single profile exists,
/// as read by `AuthBloc` on `LoginRequested`
/// (`res.data['tokens']['accessToken']`/`['refreshToken']`, `res.data['role']`).
const Map<String, dynamic> sampleLoginResponse = {
  'needsProfileSelect': false,
  'role': 'member',
  'tokens': {
    'accessToken': 'sample-access-token',
    'refreshToken': 'sample-refresh-token',
  },
};

/// Sample `POST /auth/login` response body when the account has multiple
/// profiles, as read by `AuthBloc` (`res.data['needsProfileSelect']`,
/// `res.data['selectToken']`, `res.data['profiles']`).
const Map<String, dynamic> sampleLoginNeedsProfileResponse = {
  'needsProfileSelect': true,
  'selectToken': 'sample-select-token',
  'profiles': [
    {'profileId': 'profile_1', 'label': 'Member - B-402'},
    {'profileId': 'profile_2', 'label': 'Security - Gate 1'},
  ],
};
