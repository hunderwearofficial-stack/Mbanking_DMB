import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../models/account_model.dart';
import '../models/mutation_model.dart';
import '../../core/money/money.dart';
import '../../core/services/dynamic_config_service.dart';

/// Errors (network, backend or Core Banking unavailable) are propagated as
/// ApiException so screens can show a retry message — an outage is never
/// presented as "no data" (audit DMB-026 / DMB-035).
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

  Future<List<MutationModel>> getMutations({
    int limit = 50,
    String? accountNumber,
    String? startDate,
    String? endDate,
  }) async {
    final Map<String, dynamic> query = {'limit': limit};
    if (accountNumber != null && accountNumber.isNotEmpty) {
      query['account_number'] = accountNumber;
    }
    if (startDate != null && startDate.isNotEmpty) {
      query['start_date'] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      query['end_date'] = endDate;
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
    return DynamicConfigService().config.toJson();
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

  Future<List<Map<String, dynamic>>> getLoans({String? cifNumber}) async {
    final response = await apiClient.get(
      ApiEndpoints.loans,
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is List && response.isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        response.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    if (response is Map) {
      if (response['loans'] is List && (response['loans'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          (response['loans'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      if (response['data'] is List && (response['data'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          (response['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    }

    return [];
  }

  Future<Map<String, dynamic>?> getLoanDetail(String accountNumber, {String? cifNumber}) async {
    final response = await apiClient.get(
      '${ApiEndpoints.loanDetail}$accountNumber',
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is Map) {
      if (response['detail'] is Map) {
        return Map<String, dynamic>.from(response['detail'] as Map);
      }
      if (response['data'] is Map) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      return Map<String, dynamic>.from(response);
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> getDeposits({String? cifNumber}) async {
    final response = await apiClient.get(
      ApiEndpoints.deposits,
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is List && response.isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        response.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    if (response is Map) {
      if (response['deposits'] is List && (response['deposits'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          (response['deposits'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      if (response['data'] is List && (response['data'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(
          (response['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    }

    return [];
  }

  Future<Map<String, dynamic>?> getDepositDetail(String accountNumber, {String? cifNumber}) async {
    final response = await apiClient.get(
      '${ApiEndpoints.depositDetail}$accountNumber',
      queryParameters: cifNumber != null ? {'cif_number': cifNumber} : null,
    );
    if (response is Map) {
      if (response['detail'] is Map) {
        return Map<String, dynamic>.from(response['detail'] as Map);
      }
      if (response['data'] is Map) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      return Map<String, dynamic>.from(response);
    }

    return null;
  }

  Future<Map<String, dynamic>?> getProductsCatalog() async {
    final response = await apiClient.get(ApiEndpoints.products);
    if (response is Map<String, dynamic>) {
      if (response.containsKey('tabungan')) {
        return response;
      }
      if (response['data'] is Map<String, dynamic>) {
        return response['data'] as Map<String, dynamic>;
      }
      return response;
    }

    return null;
  }

  Future<Map<String, dynamic>> submitProductApplication({
    required String productType,
    required String productName,
    required Money amount,
    required int tenorMonths,
    required String interestRate,
    required Money estimatedReturn,
    required String purposeOrSource,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.applications,
      data: {
        'product_type': productType,
        'product_name': productName,
        // Exact decimal strings (the backend parses them without floating point).
        'amount': amount.toApiString(),
        'tenor_months': tenorMonths,
        'interest_rate': interestRate,
        'estimated_return': estimatedReturn.toApiString(),
        'purpose_or_source': purposeOrSource,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return {};
  }
}

