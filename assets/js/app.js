import { LiveSocket } from "/assets/phoenix_live_view.js";
import KeyboardNav from "./hooks/keyboard_nav.js";

const hooks = {
  KeyboardNav
};

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const liveSocket = new LiveSocket("/live", hooks, { params: { _csrf_token: csrfToken } });

liveSocket.connect();
