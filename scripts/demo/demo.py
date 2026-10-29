#!/usr/bin/env python3
"""Seed and operate the isolated SRDEMO-V1 dataset through Salesforce CLI."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
BATCH = "SRDEMO-V1"
SCENARIOS = ("SUCCESS", "TIMEOUT", "HTTP_503", "HTTP_500", "INVALID_AMOUNT", "RETRY_503_2_SUCCESS")
DEFAULT_SCENARIOS = {
    "BAC_TIMEOUT_3": "TIMEOUT",
    "BAC_RETRY_SUCCESS": "RETRY_503_2_SUCCESS",
    "BAC_INVALID_AMOUNT": "INVALID_AMOUNT",
}


def sf(org, *arguments):
    completed = subprocess.run(
        ["sf", *arguments, "--target-org", org, "--json"],
        text=True, capture_output=True, timeout=180, check=False,
    )
    try:
        response = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(completed.stderr.strip() or "Salesforce CLI returned no JSON.") from error
    if completed.returncode or response.get("status", 0):
        raise RuntimeError(response.get("message", "Salesforce CLI operation failed."))
    return response["result"]


def apex(org, source):
    with tempfile.TemporaryDirectory(prefix="smartreturn-demo-") as directory:
        path = Path(directory) / "action.apex"
        path.write_text(source, encoding="utf-8")
        result = sf(org, "apex", "run", "--file", str(path))
    if not result.get("success"):
        raise RuntimeError(result.get("exceptionMessage") or result.get("compileProblem"))
    for line in result.get("logs", "").splitlines():
        if "DEMO_RESULT=" not in line:
            continue
        try:
            return json.loads(line.split("DEMO_RESULT=", 1)[1])
        except json.JSONDecodeError:
            continue
    raise RuntimeError("The action returned no DEMO_RESULT.")


def request_query(case):
    # argparse restricts case names to this script's fixed dataset.
    return f"""Return_Request__c request = [
      SELECT Id, Name, Status__c, Internal_Notes__c, Actual_Refund_Amount__c,
        Inspection_Completed_At__c, Order__r.OrderNumber
      FROM Return_Request__c WHERE External_Request_ID__c = '{BATCH}-{case}'
      WITH USER_MODE LIMIT 1
    ];"""


def arm_source(case, scenario):
    if case not in DEFAULT_SCENARIOS:
        raise ValueError("Use one of the three prepared BAC refund cases.")
    if scenario not in SCENARIOS:
        raise ValueError("Unsupported scenario.")
    # The primer consumes mock step 1. Steps 2, 3, 4 must be 503, 503, SUCCESS.
    wire_scenario = "RETRY_503_3" if scenario == "RETRY_503_2_SUCCESS" else scenario
    expected_http = {"HTTP_503": 503, "HTTP_500": 500, "INVALID_AMOUNT": 422,
                     "RETRY_503_2_SUCCESS": 503}.get(scenario)
    source = request_query(case) + """
      Assert.areEqual('INSPECTING', request.Status__c, 'The case must still be INSPECTING.');
      Assert.isNotNull(request.Inspection_Completed_At__c, 'Complete inspection first.');
      Assert.isNotNull(request.Actual_Refund_Amount__c, 'Actual refund amount is required.');
      Assert.areEqual(0, [SELECT COUNT() FROM Refund_Transaction__c
        WHERE Return_Request__c = :request.Id], 'A refund already exists. Do not re-arm.');
      Assert.isFalse(request.Internal_Notes__c.contains('[PAYHUB_ARMED:'),
        'Already armed. Do not consume another mock step; reset the dataset instead.');
      Map<String, Object> result = new Map<String, Object>();
    """
    if scenario != "SUCCESS":
        source += f"""
          HttpRequest call = new HttpRequest();
          call.setEndpoint(PayHubClient.ENDPOINT);
          call.setMethod('POST');
          call.setHeader('Content-Type', 'application/json');
          call.setHeader('Idempotency-Key', request.Name);
          call.setHeader('X-Mock-Test-Id', 'default');
          call.setHeader('X-Mock-Scenario', '{wire_scenario}');
          call.setTimeout(PayHubClient.configuredTimeoutMs());
          call.setBody(JSON.serialize(new Map<String, Object>{{
            'merchantRef' => request.Name, 'orderNumber' => request.Order__r.OrderNumber,
            'amount' => request.Actual_Refund_Amount__c, 'currency' => 'VND',
            'reason' => 'CUSTOMER_RETURN'
          }}));
        """
        if scenario == "TIMEOUT":
            source += """
              Integer delayMs = Math.max(11000, PayHubClient.configuredTimeoutMs() + 1000);
              Assert.isTrue(delayMs <= 120000, 'The demo needs a client timeout below 120 seconds.');
              call.setHeader('X-Mock-Delay-Ms', String.valueOf(delayMs));
              Boolean timedOut = false;
              try {
                new Http().send(call);
              } catch (CalloutException error) {
                String message = error.getMessage().toLowerCase();
                if (!message.contains('timed out') && !message.contains('timeout')) throw error;
                timedOut = true;
              }
              Assert.isTrue(timedOut, 'The primer must time out without accepting a payment.');
              result.put('primerTimedOut', true);
            """
        else:
            source += f"""
              HttpResponse response = new Http().send(call);
              Assert.areEqual({expected_http}, response.getStatusCode(),
                'Unexpected primer response. Check the mock before starting a refund.');
              result.put('primerHttpStatus', response.getStatusCode());
            """
    source += f"""
      request.Internal_Notes__c += ' [PAYHUB_ARMED:{scenario}]';
      update as user request;
      result.put('case', '{case}');
      result.put('scenario', '{scenario}');
      result.put('mockScenario', '{wire_scenario}');
      result.put('primerAttempts', {0 if scenario == 'SUCCESS' else 1});
      System.debug(LoggingLevel.ERROR, 'DEMO_RESULT=' + JSON.serialize(result));
    """
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org", required=True, help="Explicit Salesforce alias or username")
    commands = parser.add_subparsers(dest="command", required=True)
    seed = commands.add_parser("seed", help="Create 20 orders and 10 requests; no PayHub calls")
    seed.add_argument("--dry-run", action="store_true", help="Roll back fixtures after validation")
    seed.add_argument("--sample", action="store_true", help="Create only 3 North orders/requests: CHT, QLV and AUTO")
    commands.add_parser("status", help="Show only this dataset's requests and refunds")
    cleanup = commands.add_parser("cleanup", help="Delete only this dataset; refuses active workers/callbacks")
    cleanup.add_argument("--purge", action="store_true", help="Permanently delete demo requests/refunds to release unique keys")
    arm = commands.add_parser("arm", help="Select a safe mock scenario before a prepared refund starts")
    arm.add_argument("case", choices=tuple(DEFAULT_SCENARIOS))
    arm.add_argument("scenario", choices=SCENARIOS, nargs="?")
    start = commands.add_parser("start-refund", help="Start an inspected demo refund via RefundService")
    start.add_argument("case", choices=tuple(DEFAULT_SCENARIOS))
    retry = commands.add_parser("retry", help="Claim only the selected queued demo refund")
    retry.add_argument("case", choices=tuple(DEFAULT_SCENARIOS))
    retry.add_argument("--fast", action="store_true", help="Backdate only this fixture to skip the retry wait")
    args = parser.parse_args()

    if args.command == "seed":
        source = (ROOT / "seed.apex").read_text(encoding="utf-8")
        if args.dry_run:
            source = source.replace("Boolean dryRun = false;", "Boolean dryRun = true;", 1)
        if args.sample:
            source = source.replace("Boolean sample = false;", "Boolean sample = true;", 1)
        result = apex(args.org, source)
    elif args.command == "cleanup":
        source = (ROOT / "cleanup.apex").read_text(encoding="utf-8")
        if args.purge:
            source = source.replace("Boolean purge = false;", "Boolean purge = true;", 1)
        result = apex(args.org, source)
    elif args.command == "status":
        result = {
            "requests": sf(args.org, "data", "query", "--query", f"""
              SELECT Id, Name, External_Request_ID__c, Store__r.Store_Code__c, Status__c,
                Required_Approval_Level__c, ApproverId__r.Username, Actual_Refund_Amount__c
              FROM Return_Request__c WHERE External_Request_ID__c LIKE '{BATCH}-%'
              ORDER BY External_Request_ID__c
            """)["records"],
            "refunds": sf(args.org, "data", "query", "--query", f"""
              SELECT Name, Return_Request__r.External_Request_ID__c, Status__c,
                Attempt_Count__c, Next_Retry_At__c, Last_Error_Code__c
              FROM Refund_Transaction__c
              WHERE Return_Request__r.External_Request_ID__c LIKE '{BATCH}-%'
            """)["records"],
        }
    elif args.command == "arm":
        result = apex(args.org, arm_source(args.case, args.scenario or DEFAULT_SCENARIOS[args.case]))
    elif args.command == "start-refund":
        result = apex(args.org, request_query(args.case) + """
          Assert.isTrue(request.Internal_Notes__c.contains('[PAYHUB_ARMED:'), 'Run arm first.');
          Id refundId = RefundService.startRefund(request.Id);
          Assert.isNotNull(refundId, 'Check the Send_PayHub feature flag.');
          System.debug(LoggingLevel.ERROR, 'DEMO_RESULT=' + JSON.serialize(
            new Map<String, Object>{'refundId' => refundId, 'requestNumber' => request.Name}));
        """)
    else:
        source = request_query(args.case) + """
          Return_Request__c lockedRequest = [SELECT Id FROM Return_Request__c
            WHERE Id = :request.Id WITH USER_MODE LIMIT 1 FOR UPDATE];
          Refund_Transaction__c refund = [
            SELECT Id, Status__c, Last_Attempt_At__c, Next_Retry_At__c
            FROM Refund_Transaction__c WHERE Return_Request__c = :request.Id WITH USER_MODE
            LIMIT 1 FOR UPDATE
          ];
          Assert.areEqual('QUEUED', refund.Status__c, 'Wait for the worker; only QUEUED refunds can retry.');
        """
        if args.fast:
            source += """
              refund.Last_Attempt_At__c = System.now().addMinutes(-SmartReturnConfigService.getPayHubRetryInterval() - 1);
              refund.Next_Retry_At__c = System.now().addMinutes(-1);
              update as user refund;
            """
        result = apex(args.org, source + """
          RefundService.claimRefunds(new Set<Id>{refund.Id});
          System.debug(LoggingLevel.ERROR, 'DEMO_RESULT=' + JSON.serialize(
            new Map<String, Object>{'refundId' => refund.Id, 'requestNumber' => request.Name}));
        """)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
