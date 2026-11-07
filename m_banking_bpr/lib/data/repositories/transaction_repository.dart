import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../models/transfer_model.dart';

class TransactionRepository {
  final ApiClient apiClient;

  TransactionRepository({required this.apiClient});

  Future<TransferResponseModel> transfer(TransferRequestModel request) async {
    final response = await apiClient.post(
      ApiEndpoints.transfer,
      data: request.toJson(),
    );
    return TransferResponseModel.fromJson(response);
  }
}

