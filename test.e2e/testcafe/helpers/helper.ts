import { Selector } from "testcafe";

export class Helper {
  private static _urlPGAdmin = "http://localhost:15432/";
  private static _user: string = "postgres@example.com";
  private static _pass: string = "password";
  private static _urlGrafana = "http://localhost:3000/";

  static get urlPGAdmin() {
    return this._urlPGAdmin;
  }

  static get urlGrafana() {
    return this._urlGrafana;
  }

  static get user() {
    return this._user;
  }

  static get pass() {
    return this._pass;
  }
  //ignorovani erroru ResizeObserver
  private static explicitErrorHandler = () => {
    window.addEventListener("error", (e) => {
      if (
        e.message ===
          "ResizeObserver loop completed with undelivered notifications." ||
        e.message === "ResizeObserver loop limit exceeded"
      ) {
        e.stopImmediatePropagation();
      }
    });
  };
  static get err() {
    return this.explicitErrorHandler;
  }
}
