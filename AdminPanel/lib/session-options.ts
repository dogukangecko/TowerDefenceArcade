import type { SessionOptions } from "iron-session";

export interface SessionData {
  admin: boolean;
}

const sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret || sessionSecret.length < 32) {
  throw new Error("SESSION_SECRET eksik veya çok kısa (en az 32 karakter).");
}

export const sessionOptions: SessionOptions = {
  cookieName: "kp_session",
  password: sessionSecret,
  cookieOptions: {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
  },
};
