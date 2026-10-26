public inherited sharing class StateTransitionValidator {
  private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = buildAllowedTransitions();

  private static final Set<String> TERMINAL_STATUSES = new Set<String>{
    SmartReturnConstants.STATUS_COMPLETED,
    SmartReturnConstants.STATUS_REJECTED,
    SmartReturnConstants.STATUS_CANCELLED
  };

  private static Map<String, Set<String>> buildAllowedTransitions() {
    return new Map<String, Set<String>>{
      SmartReturnConstants.STATUS_NEW => new Set<String>{
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        SmartReturnConstants.STATUS_AWAITING_GOODS,
        SmartReturnConstants.STATUS_INSPECTING,
        SmartReturnConstants.STATUS_REJECTED,
        SmartReturnConstants.STATUS_CANCELLED
      },
      SmartReturnConstants.STATUS_PENDING_APPROVAL => new Set<String>{
        SmartReturnConstants.STATUS_AWAITING_GOODS,
        SmartReturnConstants.STATUS_INSPECTING,
        SmartReturnConstants.STATUS_REJECTED,
        SmartReturnConstants.STATUS_CANCELLED
      },
      SmartReturnConstants.STATUS_AWAITING_GOODS => new Set<String>{
        SmartReturnConstants.STATUS_INSPECTING,
        SmartReturnConstants.STATUS_CANCELLED
      },
      SmartReturnConstants.STATUS_INSPECTING => new Set<String>{
        SmartReturnConstants.STATUS_REFUND_PROCESSING,
        SmartReturnConstants.STATUS_REJECTED,
        SmartReturnConstants.STATUS_RE_CONFIRMING
      },
      SmartReturnConstants.STATUS_REFUND_PROCESSING => new Set<String>{
        SmartReturnConstants.STATUS_COMPLETED,
        SmartReturnConstants.STATUS_REFUND_FAILED
      },
      SmartReturnConstants.STATUS_REFUND_FAILED => new Set<String>{
        SmartReturnConstants.STATUS_COMPLETED
      },
      SmartReturnConstants.STATUS_RE_CONFIRMING => new Set<String>{
        SmartReturnConstants.STATUS_REFUND_PROCESSING,
        SmartReturnConstants.STATUS_REJECTED
      }
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
