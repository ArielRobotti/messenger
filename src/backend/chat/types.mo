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

    public type Participant = {
        name: Text; 
        principal:Principal
    };

    public type Chat = { 
        users : [Participant];
        msgs : [Msg]; // TODO Cambiar esta estructura por algo mas eficiente
    };

    public type ReadChatResponse = {
        #Ok: {
            #Start: {
                msgs: [Msg];
                users: [Participant];
                moreMsg: Bool;
            };
            #OnlyMsgs: {
                msgs: [Msg];
                moreMsg: Bool;
            }
        };
        #Err: Text;
    };

    public type Notice = MsgContent and {title: Text; date: Int};

    public type DiffusionChannel = {
        admin: Principal; // o admins [Principal]
        publicAccess: Bool;
        name: Text;
        users: [Participant];
        msgs: [Notice];
    }
};
