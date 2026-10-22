public inherited sharing class StateTransitionValidator {
  private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = buildAllowedTransitions();

  private static final Set<String> TERMINAL_STATUSES = new Set<String>{
    'COMPLETED',
    'REJECTED',
    'CANCELLED'
  };

  private static Map<String, Set<String>> buildAllowedTransitions() {
    return new Map<String, Set<String>>{
      'NEW' => new Set<String>{
        'PENDING_APPROVAL',
        'AWAITING_GOODS',
        'INSPECTING',
        'REJECTED',
        'CANCELLED'
      },
      'PENDING_APPROVAL' => new Set<String>{
        'AWAITING_GOODS',
        'INSPECTING',
        'REJECTED',
        'CANCELLED'
      },
      'AWAITING_GOODS' => new Set<String>{ 'INSPECTING', 'CANCELLED' },
      'INSPECTING' => new Set<String>{ 'REFUND_PROCESSING', 'REJECTED' },
      'REFUND_PROCESSING' => new Set<String>{ 'COMPLETED', 'REFUND_FAILED' },
      'REFUND_FAILED' => new Set<String>{ 'COMPLETED' }
    };
  }

  public static void validate(String oldStatus, String newStatus) {
    if (String.isBlank(oldStatus) || String.isBlank(newStatus)) {
      throw new StateTransitionException(
        'Trạng thái cũ và trạng thái mới không được để trống.'
      );
    }

    if (oldStatus == newStatus) {
      return;
    }

    if (TERMINAL_STATUSES.contains(oldStatus)) {
      throwInvalidTransition(oldStatus, newStatus);
    }

    Set<String> allowedStatuses = ALLOWED_TRANSITIONS.get(oldStatus);

    if (allowedStatuses == null || !allowedStatuses.contains(newStatus)) {
      throwInvalidTransition(oldStatus, newStatus);
    }
  }

  public static Boolean isAllowed(String oldStatus, String newStatus) {
    try {
      validate(oldStatus, newStatus);
      return true;
    } catch (StateTransitionException ex) {
      return false;
    }
  }

  public static Boolean isTerminal(String status) {
    return TERMINAL_STATUSES.contains(status);
  }

  private static void throwInvalidTransition(
    String oldStatus,
    String newStatus
  ) {
    throw new StateTransitionException(
      'Không thể chuyển yêu cầu từ ' + oldStatus + ' sang ' + newStatus + '.'
    );
  }

  public class StateTransitionException extends Exception {
  }
}
