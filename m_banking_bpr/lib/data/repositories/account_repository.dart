import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../models/account_model.dart';
import '../models/mutation_model.dart';

class AccountRepository {
  final ApiClient apiClient;

  AccountRepository({required this.apiClient});

  Future<AccountModel> getBalance({String? accountNumber}) async {
    final query = accountNumber != null ? {'account_number': accountNumber} : null;
    final response = await apiClient.get(
      ApiEndpoints.balance,
      queryParameters: query,
    );
    return AccountModel.fromJson(response);
  }

  Future<List<MutationModel>> getMutations({int limit = 20, String? accountNumber}) async {
    final Map<String, dynamic> query = {'limit': limit};
    if (accountNumber != null) {
      query['account_number'] = accountNumber;
    }

    final response = await apiClient.get(
      ApiEndpoints.mutations,
      queryParameters: query,
    );

    if (response is Map && response['mutations'] is List) {
      return (response['mutations'] as List)
          .map((m) => MutationModel.fromJson(m))
          .toList();
    } else if (response is List) {
      return response.map((m) => MutationModel.fromJson(m)).toList();
    }

    return [];
  }

  Future<Map<String, dynamic>> inquiryAccount(String accountNumber) async {
    final response = await apiClient.get(
      ApiEndpoints.accountInquiry,
      queryParameters: {'account_number': accountNumber},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return {};
  }

  Future<Map<String, dynamic>> getCustomerProfile({String? cifNumber}) async {
    final response = await apiClient.get(
      ApiEndpoints.accountProfile,
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return {};
  }

  Future<Map<String, dynamic>> getCBSCustomerProfile({String? cifNumber}) =>
      getCustomerProfile(cifNumber: cifNumber);

  Future<List<Map<String, dynamic>>> getSavingsAccounts({String? cifNumber}) async {
    final response = await apiClient.get(
      ApiEndpoints.accountList,
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is Map && response['accounts'] is List) {
      return List<Map<String, dynamic>>.from(response['accounts']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 30}) async {
    final response = await apiClient.get(
      ApiEndpoints.notifications,
      queryParameters: {'limit': limit},
    );
    if (response is List) {
      return List<Map<String, dynamic>>.from(response);
    }
    return [];
  }

  Future<void> markNotificationsRead() async {
    try {
      await apiClient.post(ApiEndpoints.notificationsRead, data: {});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final response = await apiClient.get(ApiEndpoints.appConfig);
      if (response is Map<String, dynamic>) {
        return response;
      }
    } catch (_) {}
    return {};
  }

  // ==================== SAVED BENEFICIARIES ====================

  Future<List<Map<String, dynamic>>> getBeneficiaries() async {
    try {
      final response = await apiClient.get(ApiEndpoints.beneficiaries);
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveBeneficiary({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountName,
    String nickname = '',
  }) async {
    await apiClient.post(
      ApiEndpoints.beneficiaries,
      data: {
        'bank_code': bankCode,
        'bank_name': bankName,
        'account_number': accountNumber,
        'account_name': accountName,
        'nickname': nickname,
      },
    );
  }

  Future<void> deleteBeneficiary(String id) async {
    await apiClient.delete('${ApiEndpoints.beneficiaries}/$id');
  }

  // ==================== ONLINE PRODUCT APPLICATIONS ====================

  Future<List<Map<String, dynamic>>> getUserApplications() async {
    try {
      final response = await apiClient.get(ApiEndpoints.applications);
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> submitProductApplication({
    required String productType,
    required String productName,
    required double amount,
    required int tenorMonths,
    required String interestRate,
    required double estimatedReturn,
    required String purposeOrSource,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.applications,
      data: {
        'product_type': productType,
        'product_name': productName,
        'amount': amount,
        'tenor_months': tenorMonths,
        'interest_rate': interestRate,
        'estimated_return': estimatedReturn,
        'purpose_or_source': purposeOrSource,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return {};
  }
}

