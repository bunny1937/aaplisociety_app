import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_error.dart';

sealed class PasswordResetEvent {}

class ForgotPasswordRequested extends PasswordResetEvent {
  final String identifier;
  ForgotPasswordRequested(this.identifier);
}

class ResetPasswordRequested extends PasswordResetEvent {
  final String identifier;
  final String code;
  final String newPassword;
  ResetPasswordRequested(this.identifier, this.code, this.newPassword);
}

sealed class PasswordResetState {}

class PasswordResetInitial extends PasswordResetState {}

class PasswordResetLoading extends PasswordResetState {}

class PasswordResetCodeSent extends PasswordResetState {}

class PasswordResetSuccess extends PasswordResetState {}

class PasswordResetError extends PasswordResetState {
  final String message;
  PasswordResetError(this.message);
}

/// Kept separate from AuthBloc: these screens run unauthenticated, and if
/// they shared AuthBloc, its AuthError/success states could leak into the
/// still-mounted LoginPage underneath on the nav stack (its BlocConsumer
/// listens continuously regardless of which screen is on top).
class PasswordResetBloc extends Bloc<PasswordResetEvent, PasswordResetState> {
  final Dio dio;
  PasswordResetBloc(this.dio) : super(PasswordResetInitial()) {
    on<ForgotPasswordRequested>((e, emit) async {
      emit(PasswordResetLoading());
      try {
        await dio
            .post('/auth/forgot-password', data: {'identifier': e.identifier});
        emit(PasswordResetCodeSent());
      } on DioException catch (err) {
        emit(PasswordResetError(
            apiErrorMessage(err, 'Could not send reset code')));
      }
    });
    on<ResetPasswordRequested>((e, emit) async {
      emit(PasswordResetLoading());
      try {
        await dio.post('/auth/reset-password', data: {
          'identifier': e.identifier,
          'code': e.code,
          'newPassword': e.newPassword,
        });
        emit(PasswordResetSuccess());
      } on DioException catch (err) {
        emit(PasswordResetError(
            apiErrorMessage(err, 'Could not reset password')));
      }
    });
  }
}
