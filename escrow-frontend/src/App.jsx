import { useState } from 'react';
import reactLogo from './assets/react.svg';
import './App.css';
import * as MicroStacks from '@micro-stacks/react';
import { WalletConnectButton } from './components/wallet-connect-button.jsx';
import { UserCard } from './components/user-card.jsx';
import { Logo } from './components/ustx-logo.jsx';
import { NetworkToggle } from './components/network-toggle.jsx';
import { ClientProvider, useMicroStacksClient } from '@micro-stacks/react';

function Contents() {
  return (
    <>
   
      <h1>micro-stacks + Vite + React</h1>
      <div class="card">
        <UserCard />
        <WalletConnectButton />
        <NetworkToggle />
        <p
          style={{
            display: 'block',
            marginTop: '40px',
          }}
        >
          Edit <code>src/app.jsx</code> and save to test HMR
        </p>
      </div>
      <p class="read-the-docs">Click on the micro-stacks, Vite, and React logos to learn more</p>
    </>
  );
}

export default function App() {
  const [formData, setFormData] = useState({
    seller: '',
    arbitrator: '',
    amount: 0,
  });
  const [message, setMessage] = useState('');
  // const client = useMicroStacksClient();

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const initiateEscrow = async () => {
    try {
      const functionArgs = [
        formData.seller,
        formData.arbitrator,
        parseInt(formData.amount),
      ];
      // Call the contract function (mock)
      console.log('Calling smart contract with args: ', functionArgs);
      setMessage('Escrow initiated successfully!');
    } catch (err) {
      setMessage('Error initiating escrow: ' + err.message);
    }
  };

  return (
    <MicroStacks.ClientProvider
      appName={'React + micro-stacks'}
      appIconUrl={reactLogo}
      enableNetworkSwitching={true}
    >
      {/* <Contents /> */}
      <div className="bg-retroBg min-h-screen p-8 text-retroText">
        <header className="text-center mb-10">
          <h1 className="text-4xl font-bold">Decentralized Escrow Service</h1>
          <p className="text-retroAccent">Secure your funds with peace of mind</p>
        </header>

        <main className="max-w-lg mx-auto bg-white p-6 rounded-lg shadow-md">
          <WalletConnectButton />
          <h2 className="text-2xl mb-4 font-bold">Initiate Escrow</h2>
          <div className="space-y-4">
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
              />
            </div>
            <button
              className="bg-retroAccent text-white py-2 px-4 rounded-md hover:bg-retroText"
              onClick={initiateEscrow}
            >
              Initiate Escrow
            </button>
          </div>
          {message && <p className="mt-4 text-center text-retroAccent">{message}</p>}
        </main>

        <footer className="text-center mt-10 text-sm">
          <p>&copy; {new Date().getFullYear()} Decentralized Escrow Service</p>
          <p>Retro-inspired design for modern security</p>
        </footer>
      </div>
    </MicroStacks.ClientProvider>
  );
}
