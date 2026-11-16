import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/api_endpoints.dart';
import 'package:m_banking_bpr/core/services/fcm_service.dart';

void main() {
  test('ref pengiriman hanya diterima bila berbentuk id yang valid', () {
    expect(PushPayload.ref({'ref': '8f14e45f-ceea-467a-9575-8d1e6b0f3c2a'}), '8f14e45f-ceea-467a-9575-8d1e6b0f3c2a');
    expect(PushPayload.ref({'ref': '../../admin'}), isNull);
    expect(PushPayload.ref({}), isNull);
    expect(PushPayload.ref({'ref': 123}), isNull);
  });

  test('payload ketukan notifikasi tahan terhadap isi rusak', () {
    final data = {'category': 'INFO', 'ref': 'x', 'route': 'notifications'};
    expect(PushPayload.decode(PushPayload.encode(data)), data);
    expect(PushPayload.decode(null), isEmpty);
    expect(PushPayload.decode('bukan json'), isEmpty);
    expect(PushPayload.decode('[1,2]'), isEmpty);
  });

  test('tujuan ketukan selalu halaman yang ada di aplikasi (kotak masuk)', () {
    expect(PushPayload.destination({'route': 'transfer'}), PushDestination.notifications);
    expect(PushPayload.destination({'route': 'https://contoh.invalid'}), PushDestination.notifications);
  });

  test('kanal Android dan endpoint sesuai backend', () {
    expect(FCMService.channel.id, 'dmb_notification_channel');
    expect(ApiEndpoints.notificationsFcmToken, '/api/v1/notifications/fcm-token');
    expect(ApiEndpoints.notificationsOpened, '/api/v1/notifications/opened');
  });
}
