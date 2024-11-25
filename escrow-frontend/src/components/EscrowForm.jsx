import React, { useState } from "react";
import { useOpenContractCall } from "@micro-stacks/react";
import MessageDisplay from "./MessageDisplay";
import { WalletConnectButton } from "./WalletConnectButton";
import { uintCV, principalCV} from '@stacks/transactions';
import { useAuth } from '@micro-stacks/react';



const EscrowForm = () => {
  const [formData, setFormData] = useState({
    seller: "",
    arbitrator: "",
    amount: 0,
  });
  const [message, setMessage] = useState("");

  const { openAuthRequest, isRequestPending, signOut, isSignedIn } = useAuth();
  
  const contractAddress = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
  const contractName = "subscription";
  const { openContractCall } = useOpenContractCall();
  
  const handleInputChange = (e) => {
      const { name, value } = e.target;
      setFormData({ ...formData, [name]: value });
    };
    
    const initiateEscrow = async () => {
      if (!formData.seller) {
        setMessage("Please enter a seller address");
        return;
      }

      if (!formData.arbitrator) {
        setMessage("Please enter a arbitrator address");
        return;
      }

      if (!formData.amount || parseInt(formData.amount) <= 0) {
        setMessage("Please enter a valid token amount greater than 0.");
        return;
      }

    try {
      const functionArgs1 = [
        { type: "principal", value: formData.seller },
        { type: "principal", value: formData.arbitrator },
        { type: "uint", value: formData.amount },
      ];

      const functionArgs = [
        principalCV(formData.seller),
        principalCV(formData.arbitrator),
        uintCV(parseInt(formData.amount)),
      ];


      const options = {
        contractAddress,
        contractName,
        functionName: "initiate-escrow",
        functionArgs,
        appDetails: { name: "Decentralized Escrow Service" },
        onFinish: (data) => setMessage("Transaction submitted successfully!"),
        onCancel: () => setMessage("Transaction was canceled."),
      };
      await openContractCall(options);
    } catch (err) {
      setMessage("Error initiating escrow: " + err.message);
    }
  };

  return (
    <div className="space-y-4">
      <h2 className="text-2xl mb-4 font-bold">Initiate Escrow</h2>
      <div>
        <label className="block mb-2 text-sm">Seller Address:</label>
        <input
          type="text"
          name="seller"
          className="w-full p-2 border rounded-md"
          value={formData.seller}
          onChange={handleInputChange}
        />
      </div>
      <div>
        <label className="block mb-2 text-sm">Arbitrator Address:</label>
        <input
          type="text"
          required
          name="arbitrator"
          className="w-full p-2 border rounded-md"
          value={formData.arbitrator}
          onChange={handleInputChange}
        />
      </div>
      <div>
        <label className="block mb-2 text-sm">Amount (uSTX):</label>
        <input
          type="number"
          name="amount"
          className="w-full p-2 border rounded-md"
          value={formData.amount}
          onChange={handleInputChange}
          required
        />
      </div>
      {isSignedIn && (
        <button
          className="bg-retroAccent w-full text-white py-2 px-4 rounded-md hover:bg-retroText"
          onClick={initiateEscrow}
        >
          Initiate Escrow
        </button>
      )}

      {/* <button
        className="bg-retroAccent w-full text-white py-2 px-4 rounded-md hover:bg-retroText"
        onClick={initiateEscrow}
      >
        Initiate Escrow
      </button> */}
      <WalletConnectButton />
      <MessageDisplay message={message} />
    </div>
  );
};

export default EscrowForm;
