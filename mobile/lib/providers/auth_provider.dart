import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

// Session identity and credentials have one owner; providers do not copy tokens.
final authProvider = Provider<AuthService>((ref) => AuthService.instance);
