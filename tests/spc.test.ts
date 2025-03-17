import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const parent = accounts.get("wallet_1")!;
const child = accounts.get("wallet_2")!;

describe("Secure Parental Control", () => {
    it("allows parent registration", () => {
        const registerCall = simnet.callPublicFn("spc", "register-as-parent", [], parent);
        expect(registerCall.result).toBeOk(Cl.bool(true));
    });

    it("allows setting allowance for child", () => {
        // Register parent first
        simnet.callPublicFn("spc", "register-as-parent", [], parent);
        
        const setAllowanceCall = simnet.callPublicFn(
            "spc",
            "set-allowance",
            [Cl.principal(child), Cl.uint(100)],
            parent
        );
        expect(setAllowanceCall.result).toBeOk(Cl.bool(true));
    });

    it("allows child to spend within allowance", () => {
        // Setup
        simnet.callPublicFn("spc", "register-as-parent", [], parent);
        simnet.callPublicFn(
            "spc",
            "set-allowance",
            [Cl.principal(child), Cl.uint(100)],
            parent
        );

        // Test spending
        const spendCall = simnet.callPublicFn(
            "spc",
            "spend",
            [Cl.uint(50)],
            child
        );
        expect(spendCall.result).toBeOk(Cl.bool(true));

        // Verify remaining balance
        const allowanceCall = simnet.callReadOnlyFn(
            "spc",
            "get-allowance",
            [Cl.principal(child)],
            child
        );
        expect(allowanceCall.result).toEqual(Cl.tuple({
            amount: Cl.uint(50),
            parent: Cl.principal(parent)
        }));
    });});
