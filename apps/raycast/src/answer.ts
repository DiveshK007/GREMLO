import { LaunchProps } from "@raycast/api";
import { run } from "./socket";
// The app refuses to allow a risky command (delete, push, spend) from here; those need a click on the notch.
export default async (p: LaunchProps<{ arguments: { answer?: string } }>) => run("approve", { answer: p.arguments.answer === "deny" ? "deny" : "allow" });
