# Secure Parental Control for Digital Allowance

A blockchain-based solution for managing children's digital allowances using Clarity smart contracts on the Stacks network.

## Overview

This project implements a secure parental control system that enables parents to:
- Register as authorized parents
- Set and manage digital allowances for their children
- Monitor spending activities

Children can:
- View their available allowance
- Spend within their allocated limits

## Smart Contract Features

### Core Functions

#### For Parents
- `register-as-parent`: Register a wallet address as a parent
- `set-allowance`: Set or update allowance amount for a specific child
- `is-parent`: Check if an address is registered as a parent

#### For Children
- `spend`: Execute spending within available allowance
- `get-allowance`: Check current allowance balance

### Error Codes
- `ERR-NOT-AUTHORIZED (u100)`: Triggered when non-parent attempts restricted actions
- `ERR-INSUFFICIENT-BALANCE (u101)`: Triggered when spending exceeds available allowance

## Technical Implementation

### Data Structure
The contract uses three main data maps:
- `parents`: Tracks registered parent addresses
- `allowances`: Stores allowance amounts and parent-child relationships
- `spending-history`: Records spending patterns and history

### Testing

The test suite covers:
1. Parent registration functionality
2. Allowance setting mechanisms
3. Spending operations
4. Balance verification

### Prerequisites
- Clarinet
- Node.js
- Vitest for testing

