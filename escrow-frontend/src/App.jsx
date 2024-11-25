// import React, { useState } from "react";
// import { ClientProvider, useOpenContractCall, useAuth } from "@micro-stacks/react";
// import { principalCV, uintCV } from "@stacks/transactions"; // Clarity argument types
// import reactLogo from "./assets/react.svg";

// export default function App() {
//   const [formData, setFormData] = useState({
//     seller: "",
//     arbitrator: "",
//     amount: "",
//   });
//   const [message, setMessage] = useState("");
//   const [loading, setLoading] = useState(false);

//   const contractAddress = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"; // Replace with actual contract address
//   const contractName = "escrow-service"; // Replace with your contract name

//   const { isSignedIn, signIn, signOut } = useAuth();
//     const { openContractCall } = useOpenContractCall();

//   const handleInputChange = (e) => {
//     const { name, value } = e.target;
//     setFormData((prev) => ({ ...prev, [name]: value }));
//   };

//   const initiateEscrow = async () => {
//     if (!isSignedIn) {
//       setMessage("❌ Please connect your wallet to initiate escrow.");
//       return;
//     }

//     const { seller, arbitrator, amount } = formData;

//     if (!seller || !arbitrator || !amount || parseInt(amount) <= 0) {
//       setMessage("❌ All fields are required, and amount must be greater than 0.");
//       return;
//     }

//     setLoading(true);
//     setMessage("");

//     try {
//       const functionArgs = [
//         principalCV(seller),
//         principalCV(arbitrator),
//         uintCV(parseInt(amount)),
//       ];

//       const options = {
//         contractAddress,
//         contractName,
//         functionName: "initiate-escrow",
//         functionArgs,
//         appDetails: { name: "Decentralized Escrow Service" },
//         onFinish: (data) => {
//           console.log("Transaction successful:", data);
//           setMessage("🎉 Escrow initiated successfully!");
//         },
//         onCancel: () => {
//           setMessage("❌ Transaction canceled.");
//         },
//       };

//       await openContractCall(options);
//     } catch (error) {
//       console.error("Error initiating escrow:", error);
//       setMessage("❌ Failed to initiate escrow: " + error.message);
//     } finally {
//       setLoading(false);
//     }
//   };

//   return (
//     <MicroStacks.ClientProvider appName="Decentralized Escrow Service" appIconUrl={reactLogo}>
//       <div className="min-h-screen bg-gray-100 flex items-center justify-center p-8">
//         <div className="max-w-md w-full bg-white shadow-md rounded-lg p-6">
//           <header className="mb-6">
//             <h1 className="text-2xl font-bold text-gray-700">Decentralized Escrow</h1>
//             <p className="text-sm text-gray-500">Secure your transactions with ease</p>
//           </header>

//           {!isSignedIn ? (
//             <button
//               onClick={signIn}
//               className="w-full bg-blue-500 text-white py-2 rounded-lg font-bold hover:bg-blue-600 transition"
//             >
//               Connect Wallet
//             </button>
//           ) : (
//             <>
//               <div className="space-y-4">
//                 <div>
//                   <label className="block text-sm text-gray-600 mb-1">Seller Address</label>
//                   <input
//                     type="text"
//                     name="seller"
//                     placeholder="Enter seller address"
//                     value={formData.seller}
//                     onChange={handleInputChange}
//                     className="w-full p-3 border rounded-lg"
//                   />
//                 </div>
//                 <div>
//                   <label className="block text-sm text-gray-600 mb-1">Arbitrator Address</label>
//                   <input
//                     type="text"
//                     name="arbitrator"
//                     placeholder="Enter arbitrator address"
//                     value={formData.arbitrator}
//                     onChange={handleInputChange}
//                     className="w-full p-3 border rounded-lg"
//                   />
//                 </div>
//                 <div>
//                   <label className="block text-sm text-gray-600 mb-1">Amount (uSTX)</label>
//                   <input
//                     type="number"
//                     name="amount"
//                     placeholder="Enter amount"
//                     value={formData.amount}
//                     onChange={handleInputChange}
//                     className="w-full p-3 border rounded-lg"
//                   />
//                 </div>
//               </div>

//               <button
//                 onClick={initiateEscrow}
//                 className={`w-full mt-4 py-2 rounded-lg font-bold ${
//                   loading
//                     ? "bg-gray-400 cursor-not-allowed"
//                     : "bg-green-500 hover:bg-green-600 text-white"
//                 }`}
//                 disabled={loading}
//               >
//                 {loading ? "Processing..." : "Initiate Escrow"}
//               </button>

//               <button
//                 onClick={signOut}
//                 className="w-full mt-4 bg-red-500 text-white py-2 rounded-lg font-bold hover:bg-red-600 transition"
//               >
//                 Disconnect Wallet
//               </button>
//             </>
//           )}

//           {message && (
//             <p
//               className={`mt-4 text-center font-medium ${
//                 message.includes("success") ? "text-green-500" : "text-red-500"
//               }`}
//             >
//               {message}
//             </p>
//           )}
//         </div>
//       </div>
//     </MicroStacks.ClientProvider>
//   );
// }


import React from "react";
import { ClientProvider } from "@micro-stacks/react";
import EscrowForm from "./components/EscrowForm";
import Header from "./components/Header";
import Footer from "./components/Footer";
import reactLogo from "./assets/react.svg";
import * as MicroStacks from '@micro-stacks/react';


const App = () => {
  return (
    <MicroStacks.ClientProvider
      appName={"React + micro-stacks"}
      appIconUrl={reactLogo}
      enableNetworkSwitching={true}
    >
      <div className="bg-retroBg min-h-screen p-8 text-retroText">
        <Header />
        <main className="max-w-lg mx-auto bg-white p-6 rounded-lg shadow-md">
          <EscrowForm />
        </main>
        <Footer />
      </div>
    </MicroStacks.ClientProvider>
  );
};

export default App;
