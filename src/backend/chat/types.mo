module {

    public type ChatId = Nat32; //Hash concatenacion de principals ordenados de menor a mayor
    public type StorageIndex = {
        canisterId : Principal;
        index : Nat;
    };
    public type MsgContent = {
        msg : Text;
        multimedia : ?StorageIndex;
    };
    public type Msg = MsgContent and {
        date: Int;
        sender: Nat; // Index en la lista de users
        indexMsg: Nat;  // Para acceder en tiempo constante
    };

    public type Chat = { 
        users : [{name: Text; principal:Principal}];
        msgs : [Msg]; // TODO Cambiar esta estructura por algo mas eficiente
    };

    public type ReadChatResponse = {
        #Ok: {
            #Start: {
                msgs: [Msg];
                users: [{name: Text; principal:Principal}];
                moreMsg: Bool;
            };
            #OnlyMsgs: {
                msgs: [Msg];
                moreMsg: Bool;
            }
        };
        #Err: Text;
    }
};
