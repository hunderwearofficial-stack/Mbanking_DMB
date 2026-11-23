import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../models/account_model.dart';
import '../models/mutation_model.dart';
import '../../core/money/money.dart';
import '../../core/services/dynamic_config_service.dart';

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
    final page = await getMutationsPage(
      limit: limit,
      accountNumber: accountNumber,
      startDate: startDate,
      endDate: endDate,
    );
    return page.items;
  }

  /// Newest mutations of the period plus whether the period holds more transactions
  /// than returned (server flag `has_more`, audit MA-02).
  Future<MutationPage> getMutationsPage({
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
      return MutationPage(
        items: (response['mutations'] as List).map((m) => MutationModel.fromJson(m)).toList(),
        hasMore: response['has_more'] == true,
      );
    } else if (response is List) {
      return MutationPage(items: response.map((m) => MutationModel.fromJson(m)).toList());
    }

    return const MutationPage(items: []);
  }

  /// Unmasked identity data, released by the server only after it verified the PIN.
  Future<Map<String, dynamic>> revealCustomerProfile(String pin) async {
    final response = await apiClient.post(ApiEndpoints.accountProfileReveal, data: {'pin': pin});
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{};
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
    String interestRate = '',
    Money estimatedReturn = const Money.zero(),
    String purposeOrSource = '',
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.applications,
      data: {
        'product_type': productType,
        'product_name': productName,
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

/// One page of mutations: the newest [items] of the period and whether more exist.
class MutationPage {
  final List<MutationModel> items;
  final bool hasMore;

  const MutationPage({required this.items, this.hasMore = false});
}
