import 'dart:async';

import 'ws_client.dart';

enum AppNotificationType {
  messageCreated,
  invitationReceived,
  invitationAccepted,
}

class AppNotificationEvent {
  final AppNotificationType type;
  final String title;
  final String body;
  final String? threadId;
  final String? messageId;
  final Map<String, dynamic> raw;

  const AppNotificationEvent({
    required this.type,
    required this.title,
    required this.body,
    required this.raw,
    this.threadId,
    this.messageId,
  });
}

class NotificationsService {
  final WebSocketClient _wsClient;
  final StreamController<AppNotificationEvent> _controller = StreamController<AppNotificationEvent>.broadcast();

  Stream<AppNotificationEvent> get stream => _controller.stream;

  NotificationsService({required WebSocketClient wsClient}) : _wsClient = wsClient {
    _registerHandlers();
  }

  void _registerHandlers() {
    _wsClient.registerMessageHandler('message_created', _onMessageCreated);
    _wsClient.registerMessageHandler('thread_invitation', _onInvitationReceived);
    _wsClient.registerMessageHandler('invitation_accepted', _onInvitationAccepted);
  }

  void _onMessageCreated(Map<String, dynamic> msg) {
    final String? threadId = msg['parent_thread'] as String? ?? msg['thread_id'] as String?;
    final String? messageId = msg['id'] as String?;
    // final String fromUserId = (msg['user_id'] ?? '') as String;
    _controller.add(AppNotificationEvent(
      type: AppNotificationType.messageCreated,
      title: 'Pattern updated',
      body: 'New update in a pattern',
      threadId: threadId,
      messageId: messageId,
      raw: msg,
    ));
  }

  void _onInvitationReceived(Map<String, dynamic> msg) {
    final String threadId = (msg['thread_id'] ?? '') as String;
    final String fromName = (msg['from_user_name'] ?? 'Someone') as String;
    _controller.add(AppNotificationEvent(
      type: AppNotificationType.invitationReceived,
      title: 'Invitation received',
      body: '$fromName invited you to collaborate',
      threadId: threadId,
      raw: msg,
    ));
  }

  void _onInvitationAccepted(Map<String, dynamic> msg) {
    final String threadId = (msg['thread_id'] ?? '') as String;
    final String userName = (msg['user_name'] ?? 'A collaborator') as String;
    _controller.add(AppNotificationEvent(
      type: AppNotificationType.invitationAccepted,
      title: 'Invitation accepted',
      body: '$userName accepted invitation',
      threadId: threadId,
      raw: msg,
    ));
  }

  void dispose() {
    _wsClient.unregisterAllHandlers('message_created');
    _wsClient.unregisterAllHandlers('thread_invitation');
    _wsClient.unregisterAllHandlers('invitation_accepted');
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}


