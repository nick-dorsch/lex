import { Socket } from "/assets/phoenix.js";
import { LiveSocket } from "/assets/phoenix_live_view.js";
import KeyboardNav from "./hooks/keyboard_nav.js";
import LLMPopup from "./hooks/llm_popup.js";

const hooks = {
  KeyboardNav,
  LLMPopup
};

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: { _csrf_token: csrfToken }
});

liveSocket.connect();
