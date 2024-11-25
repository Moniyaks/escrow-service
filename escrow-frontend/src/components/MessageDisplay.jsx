import React from "react";

const MessageDisplay = ({ message }) => {
  return message ? (
    <p className="mt-4 text-center text-retroAccent">{message}</p>
  ) : null;
};

export default MessageDisplay;
