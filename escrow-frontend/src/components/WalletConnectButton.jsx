import { useAuth } from '@micro-stacks/react';

export const WalletConnectButton = () => {
  const { openAuthRequest, isRequestPending, signOut, isSignedIn } = useAuth();

  const handleClick = () => {
    if (isSignedIn) {
      void signOut();
    } else {
      void openAuthRequest();
    }
  };

  const label = isRequestPending
    ? 'Loading...'
    : isSignedIn
    ? 'Sign out'
    : 'Connect Stacks Wallet';

  return (
    <div className="mb-4">
      <button
        onClick={handleClick}
        className={`py-2 px-4 w-full rounded-md ${
          isSignedIn ? 'bg-red-500 text-white' : 'bg-blue-500 text-white'
        }`}
        disabled={isRequestPending}
      >
        {label}
      </button>
    </div>
  );
};

export default WalletConnectButton;
