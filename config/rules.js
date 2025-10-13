// File: config/rules.js
// This file defines the signing rules for Clef. It allows for the automation of
// specific signing tasks, like sealing PoA blocks, while maintaining security by
// rejecting other types of requests by default.

/**
 * This function is called once when the Clef signer starts. It can be left empty
 * or used for logging startup information.
 * @param {object} info - Information about the signer startup.
 */
function OnSignerStartup(info) {
  // For debugging, you can uncomment the following line:
  // console.log("Clef Signer Started: ", JSON.stringify(info));
}

/**
 * This function allows a client (like Geth) to list the accounts managed by this Clef instance.
 * Returning "Approve" is essential for Geth to identify which account to use when the
 * --signer flag is active.
 * @returns {string} - "Approve" to allow account listing.
 */
function ApproveListing() {
  return "Approve";
}

/**
 * This function is called by Clef for every data signing request that requires approval.
 * It uses the 'CLEF_MODE' environment variable to switch between a secure default
 * and a permissive benchmark mode.
 * * @param {object} r - The request object from Clef, containing details about the signing request.
 * @returns {string} "Approve" or "Reject".
 */
function ApproveSignData(r) {
  // Only approve Clique consensus headers, which are necessary for the PoA network to function.
  if (r.content_type == "application/x-clique-header") {
    for (var i = 0; i < r.messages.length; i++) {
      var msg = r.messages[i];
      if (msg.name == "Clique header" && msg.type == "clique") {
        console.log(
          ">>> [SECURE MODE] Approved Clique header signing for block: ",
          msg.value
        );
        return "Approve";
      }
    }
  }

  // Reject everything else by default.
  console.log(">>> [SECURE MODE] Denied signing request:", JSON.stringify(r));
  return "Reject";
}

/**
 * This function handles transaction signing requests.
 * In a pure PoA setup, the signer's primary role is to seal blocks, not to send transactions.
 * @param {object} r - The transaction request object.
 * @returns {string} - "Reject" to block all outgoing transactions from this account.
 */
function ApproveTx(r) {
  console.log("Received Tx request: ", JSON.stringify(r));
  // For maximum security, we will reject all outgoing transaction requests from this account.
  // If transactions need to be sent, they should originate from a different, non-signer account.
  return "Reject";
}
