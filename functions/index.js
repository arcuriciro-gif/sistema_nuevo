/**
 * Push FCM cuando hay notificación interna o push_request.
 * Deploy: `firebase deploy --only functions` (proyecto tata-stock-8631e).
 * Requiere plan Blaze.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

async function tokensForUser(tenantId, usuario) {
  const snap = await admin
    .firestore()
    .collection("tenants")
    .doc(tenantId)
    .collection("fcm_tokens")
    .where("usuario", "==", usuario)
    .get();
  return snap.docs
    .map((d) => d.data().token)
    .filter((t) => typeof t === "string" && t.length > 20);
}

async function sendToUser({ tenantId, usuario, titulo, cuerpo, payload }) {
  const tokens = await tokensForUser(tenantId, usuario);
  if (!tokens.length) {
    functions.logger.info("sin tokens", { tenantId, usuario });
    return { sent: 0 };
  }
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: titulo || "Tata.Manager",
      body: cuerpo || "Tenés un aviso nuevo",
    },
    data: {
      titulo: String(titulo || "Tata.Manager"),
      cuerpo: String(cuerpo || "Tenés un aviso nuevo"),
      payload: String(payload || "notif"),
    },
    android: {
      priority: "high",
      notification: {
        channelId: "tata_manager_avisos",
        priority: "high",
      },
    },
  });
  return { sent: res.successCount, failure: res.failureCount };
}

exports.onNotificacionCreate = functions.firestore
  .document("tenants/{tenantId}/notificaciones/{notifId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const usuario = data.usuarioDestino;
    if (!usuario) return null;
    const conv = data.conversacionId;
    const payload =
      conv && String(conv).length > 0 ? `chat:${conv}` : "notif";
    return sendToUser({
      tenantId: context.params.tenantId,
      usuario,
      titulo: data.titulo,
      cuerpo: data.cuerpo,
      payload,
    });
  });

exports.onPushRequestCreate = functions.firestore
  .document("tenants/{tenantId}/push_requests/{reqId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    if (data.status && data.status !== "pending") return null;
    const usuario = data.usuarioDestino;
    if (!usuario) return null;
    const result = await sendToUser({
      tenantId: context.params.tenantId,
      usuario,
      titulo: data.titulo,
      cuerpo: data.cuerpo,
      payload: data.payload || "notif",
    });
    await snap.ref.set(
      {
        status: "sent",
        sentAt: new Date().toISOString(),
        result,
      },
      { merge: true }
    );
    return result;
  });
