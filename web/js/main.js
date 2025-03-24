import { fetchNui } from "./fetchNui.js";
import { createOptions } from "./createOptions.js";

const optionsWrapper = document.getElementById("options-wrapper");
const body = document.body;
let menuVisible = false;

document.addEventListener('keydown', (event) => {
  if (menuVisible && (event.key === 'Escape' || event.key === 'Backspace')) {
    menuVisible = false;
    body.style.visibility = 'hidden';
    fetchNui("close");
  }
});

window.addEventListener("message", (event) => {
  optionsWrapper.innerHTML = "";

  switch (event.data.event) {
    case "visible": {
      menuVisible = event.data.state;
      return body.style.visibility = event.data.state ? "visible" : "hidden";
    }

    case "setTarget": {
      if (event.data.options) {
        for (const type in event.data.options) {
          event.data.options[type].forEach((data, id) => {
            createOptions(type, data, id + 1);
          });
        }
      }

      if (event.data.zones) {
        for (let i = 0; i < event.data.zones.length; i++) {
          event.data.zones[i].forEach((data, id) => {
            createOptions("zones", data, id + 1, i + 1);
          });
        }
      }

      createOptions("close", {
        icon: "fa-times",
        label: "Fermer"
      }, 0);

      const x = Math.min(event.data.cursorX * window.innerWidth, window.innerWidth - optionsWrapper.offsetWidth);
      const y = Math.min(event.data.cursorY * window.innerHeight, window.innerHeight - optionsWrapper.offsetHeight);
      optionsWrapper.style.left = `${x}px`;
      optionsWrapper.style.top = `${y}px`;
    }
  }
});