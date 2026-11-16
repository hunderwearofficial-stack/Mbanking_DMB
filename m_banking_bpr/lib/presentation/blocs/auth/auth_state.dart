import 'package:equatable/equatable.dart';
import '../../../data/models/user_model.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  /// Backend response code, e.g. '10' = Terms and Conditions in force not yet accepted,
  /// '11' = no Terms published yet.
  final String? code;
  const AuthError(this.message, {this.code});

  /// The customer must read and accept the Terms in force before continuing.
  bool get requiresTermsConsent => code == '10';

  @override
  List<Object?> get props => [message, code];
}

