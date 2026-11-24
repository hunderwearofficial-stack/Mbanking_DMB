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

  final String? code;
  const AuthError(this.message, {this.code});

  bool get requiresTermsConsent =>
      code == '10' && message.toLowerCase().contains('syarat dan ketentuan');

  @override
  List<Object?> get props => [message, code];
}

